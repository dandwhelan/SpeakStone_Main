local addonName, addon = ...

-- The speech frame: who is talking, what they are saying, and pause / stop /
-- replay, for narration that carries on after its window has closed -- the
-- player walked away, or the quest was auto-accepted (owner, 2026-10-05).
-- The cinematic-bar layout from docs/npc-speech-frame-mockups.html. The
-- text is shown whole, scrolled with the mouse wheel; following the voice
-- line by line is for later.
--
-- Driven by three notices from the playback code in SpeakStone_Main.lua --
-- "start", "finish" and "stop" -- and by the clip's own soundData, which
-- carries the text, title and NPC captured at play time.
--
-- Two limits are the client's:
-- * Nothing reports where a clip is. The timer is worked out from when it
--   started (soundData.startedAt) and its length (SoundLengths).
-- * PlaySoundFile has no pause and cannot start part-way into a file. Pause
--   stops the clip; Resume plays it again from the top, or, for a long clip
--   its pack stores in chunks (ClipChunks.lua), from the chunk it paused in.

local SIZES = {
    { key = "small", label = "Small", scale = 0.8 },
    { key = "medium", label = "Medium", scale = 1.0 },
    { key = "large", label = "Large", scale = 1.25 },
    { key = "xlarge", label = "Extra large", scale = 1.5 },
}

-- A little bigger than the first cut (660 x 130, 72 portrait; owner, 2026-11-12: "a little bit bigger").
local WIDTH, HEIGHT = 720, 146
local PORTRAIT = 84
local TEXT_LINES = 4
-- Text size and how many lines show at once (owner, 2026-11-18: for a television across the room, bigger text,
-- three or four lines at a time, gliding up as it is read). Points added to the reading font's size.
-- Small and Medium added 2026-11-25 (owner: "add small and medium text options").
local TEXT_SIZES = {
    { key = "small", label = "Small", add = -3 },
    { key = "medium", label = "Medium", add = -2 },
    { key = "normal", label = "Normal", add = 0 },
    { key = "large", label = "Large", add = 3 },
    -- The TV / controller default (owner, 2026-11-19: "a little under Extra large"). Listed so it can be picked
    -- again: until 2026-11-28 it was only the unset value, and once another size was picked it was gone for good.
    { key = "tv", label = "Larger (TV default)", add = 5 },
    { key = "xlarge", label = "Extra large", add = 7 },
}
-- TV / controller size keeps its own choices (speechTVSize, speechTVTextSize), so picking a size from the
-- menu while a controller is in use changes what is on screen. Until 2026-11-25 TV mode forced 1.25 and +5
-- and the menu wrote the mouse-and-keyboard keys instead: every pick looked like it did nothing.
local TV_SIZE_DEFAULT = "large"        -- scale 1.25
local TV_TEXT_DEFAULT = "tv"           -- +5, a little under "Extra large"
local BASE_LINE = 15      -- the normal font's row height: HEIGHT was laid out for TEXT_LINES of these
local SCROLL_EASE = 5     -- how fast the text glides to where it should be (higher = snappier)
-- "Show all the text": the most lines the frame grows to before it scrolls.
local MAX_FIT_LINES = 24
-- How long the frame stays up after a line ends on its own.
local LINGER_SECONDS = 2
local UPDATE_INTERVAL = 0.1
-- Top of the screen by default: out of the way of action bars and the controller's on-screen hints, and
-- reachable for controller players who cannot drag it (owner, 2026-11-17).
local DEFAULT_POINT = { "TOP", "TOP", 0, -110 }

local PREVIEW_TEXT = "This is the SpeakStone speech bar. It appears when you walk away from a quest giver while "
    .. "narration is still going, or when a quest is auto-accepted, so you can read along and pause or stop the "
    .. "voice. Drag it where you want it. Right-click it, or use the gear, to change its size, lock it in place or "
    .. "reset its position. Scroll with the mouse wheel when a quest has more text than fits. Close it with the X "
    .. "or Stop when you are done."

-- --------------------------------------------------------------------------
-- State
-- --------------------------------------------------------------------------

local frame, driver
local current          -- the soundData on show
local paused = false
local pausedElapsed = 0
local lingerUntil = nil
local pausing = false  -- our own Pause is the one calling StopCurrentSound

local function DB()
    return SpeakStone_ForeverMainDB or SpeakStone_MainDB or {}
end

local function Readable(value)
    if type(value) ~= "string" then
        return nil
    end
    -- Secret check must come before any comparison: `value == ""` on a secret string taints/errors.
    if addon.IsSecret and addon.IsSecret(value) then
        return nil
    end
    if value == "" then
        return nil
    end
    return value
end

-- TV / Sofa size: bigger bar, large text, gliding lines. Active whenever
-- "TV / Sofa" layout is chosen (speechTVAlways) or automatically while a
-- controller is in use (speechTVOnPad).
local function TVNow()
    return DB().speechTVAlways == true or (DB().speechTVOnPad and addon.padActive)
end

-- The saved-variable keys the bar's size and text size read right now: the TV ones while TV size is in force.
local function SizeKeyName()
    return TVNow() and "speechTVSize" or "speechSize"
end

local function TextKeyName()
    return TVNow() and "speechTVTextSize" or "speechTextSize"
end

local function CurrentSizeKey()
    if TVNow() then return DB().speechTVSize or TV_SIZE_DEFAULT end
    return DB().speechSize or "medium"
end

local function CurrentTextKey()
    if TVNow() then return DB().speechTVTextSize or TV_TEXT_DEFAULT end
    return DB().speechTextSize or "normal"
end

local function SizeScale()
    local key = CurrentSizeKey()
    for _, size in ipairs(SIZES) do
        if size.key == key then
            return size.scale
        end
    end
    return 1
end

local function TextAdd()
    local key = CurrentTextKey()
    for _, size in ipairs(TEXT_SIZES) do
        if size.key == key then return size.add end
    end
    return 0
end

-- Compact (owner, 2026-11-18; four lines and a smooth roll, 2026-11-19): four lines that scroll with the voice, whatever "grow to show all the
-- text" says, so a big box of quest text doesn't sit in the middle of the screen while walking around.
-- Always on with a controller; mouse and keyboard players can pick it (speechCompact).
local function Compact()
    return addon.padActive or DB().speechTVAlways == true or DB().speechCompact == true
end

-- The player's "Lines at a time" pick wins in compact and on a controller too (until 2026-11-25 those forced 4
-- and the menu's 3 did nothing).
local function Lines()
    local n = tonumber(DB().speechLines)
    return (n == 3 or n == 4) and n or TEXT_LINES
end

-- In combat the bar can stay, fade back or get out of the way; the voice carries on either way.
local function CombatMode()
    local mode = DB().speechCombat
    return (mode == "fade" or mode == "hide") and mode or "show"
end

-- On a flight path, or a cutscene playing: the bar steps aside (the voice carries on).
local function SteppedAside()
    if DB().speechHideOnTaxi == true and UnitOnTaxi and UnitOnTaxi("player") then
        return true
    end
    if (InCinematic and InCinematic()) or (CinematicFrame and CinematicFrame:IsShown())
        or (MovieFrame and MovieFrame:IsShown()) then
        return true
    end
    return false
end

-- The soft edges (owner, 2026-11-19). Each edge is a stack of thin strips in the paper's colour, solid at the
-- edge and clear toward the middle: a gradient that needs no client gradient API (SetGradient drew a flat band
-- in game). Over Dialogue UI's paper the colour is that art's own (measured in game, tinted like the frame);
-- over the flat band it is the theme's background.
local FADE_MAX = 0.95
local COMBAT_FADE_ALPHA = 0.6
local FADE_STRIPS = 10
local PAPER = { 0.80, 0.655, 0.46 }

local function PaintFades(theme, art)
    if not frame or not frame.fades then return end
    local c
    if art then
        local t = theme.tint or { 1, 1, 1 }
        c = { PAPER[1] * t[1], PAPER[2] * t[2], PAPER[3] * t[3] }
    else
        c = theme.back or { 0, 0, 0 }
    end
    for _, edge in ipairs({ frame.fades.top, frame.fades.bottom }) do
        for i, strip in ipairs(edge.strips) do
            -- Strip 1 sits at the edge. Eased, so the text dissolves rather than meeting a line.
            local a = FADE_MAX * ((FADE_STRIPS - i + 0.5) / FADE_STRIPS) ^ 1.6
            strip:SetColorTexture(c[1], c[2], c[3], a)
        end
    end
end

-- Lay an edge's strips out over `height`, from its outer edge inward.
local function PlaceStrips(edge, height, fromTop)
    if edge.placed == height then return end
    edge.placed = height
    edge:SetHeight(height)
    local h = height / FADE_STRIPS
    for i, strip in ipairs(edge.strips) do
        strip:ClearAllPoints()
        strip:SetHeight(h)
        if fromTop then
            strip:SetPoint("TOPLEFT", edge, "TOPLEFT", 0, -(i - 1) * h)
            strip:SetPoint("TOPRIGHT", edge, "TOPRIGHT", 0, -(i - 1) * h)
        else
            strip:SetPoint("BOTTOMLEFT", edge, "BOTTOMLEFT", 0, (i - 1) * h)
            strip:SetPoint("BOTTOMRIGHT", edge, "BOTTOMRIGHT", 0, (i - 1) * h)
        end
    end
end

-- Each edge shows only while text is hidden past it, coming in over the first line of scrolling.
local function UpdateFades(scroll)
    local fades = frame and frame.fades
    if not fades then return end
    local line = frame.lineHeight or 15
    local range = scroll:GetVerticalScrollRange() or 0
    -- Faded for combat the paper is see-through, and the edges (paper-coloured strips over the text) stood out
    -- as solid bands across it (owner's screenshot, 2026-11-23): no edges then.
    if range <= 0 or frame.combatFaded then
        fades.top:SetAlpha(0)
        fades.bottom:SetAlpha(0)
        return
    end
    local height = math.floor(line * 1.2 + 0.5)
    PlaceStrips(fades.top, height, true)
    PlaceStrips(fades.bottom, height, false)
    local now = scroll:GetVerticalScroll() or 0
    fades.top:SetAlpha(math.max(0, math.min(1, now / line)))
    fades.bottom:SetAlpha(math.max(0, math.min(1, (range - now) / line)))
end

-- Narrator parts (owner, 2026-11-19 / 2026-11-22): <...> stage directions are laid out as their own blocks,
-- indented, wrapped in *...*, a size smaller, in the theme's quieter ink, and in the bundled italic font when
-- the client can load it (requires a full client restart after install; falls back to the reading/game font).
local NARR_INDENT = 14

local function Segments(plain)
    local segs = {}
    if not plain:find("|", 1, true) then
        local para, pa, inDirection = 0, 1, false
        while pa <= #plain do
            local s, e = plain:find("\n[ \t]*\n", pa)
            local pb = s and (s - 1) or #plain
            para = para + 1
            local run
            for rs, re in plain:sub(pa, pb):gmatch("()%S+()") do
                local ts, te = rs + pa - 1, re + pa - 2
                local word = plain:sub(ts, te)
                if word:sub(1, 1) == "<" then inDirection = true end
                local narr = inDirection
                if inDirection and word:sub(-1) == ">" then inDirection = false end
                if run and run.narr == narr then
                    run.b = te
                else
                    run = { a = ts, b = te, narr = narr, para = para }
                    segs[#segs + 1] = run
                end
            end
            pa = e and (e + 1) or (#plain + 1)
        end
    end
    if #segs == 0 then
        segs[1] = { a = 1, b = #plain, para = 1 }
    end
    for _, seg in ipairs(segs) do
        seg.da, seg.db = seg.a, seg.b
        if seg.narr then
            if plain:sub(seg.da, seg.da) == "<" then seg.da = seg.da + 1 end
            if plain:sub(seg.db, seg.db) == ">" then seg.db = seg.db - 1 end
        end
    end
    return segs
end
addon.SpeechSegments = Segments   -- for the tests

-- One block's text, the marked words wrapped in the highlight colour; dimCode dims the whole block.
local function SegText(plain, seg, marks, code, dimCode)
    local out, from = {}, seg.da
    for _, t in ipairs(marks or {}) do
        local s, e = math.max(t.s, seg.da), math.min(t.e, seg.db)
        if s <= e and s >= from then
            out[#out + 1] = plain:sub(from, s - 1)
            out[#out + 1] = code .. plain:sub(s, e) .. "|r"
            from = e + 1
        end
    end
    out[#out + 1] = plain:sub(from, seg.db)
    local str = table.concat(out)
    if seg.narr and str ~= "" then
        str = "*" .. str .. "*"
    end
    if dimCode and str ~= "" then
        str = dimCode .. str .. "|r"
    end
    return str
end

local function PlainSegTexts()
    local texts = {}
    for i, seg in ipairs(frame.segs) do
        local s = frame.plain:sub(seg.da, seg.db)
        if seg.narr and s ~= "" then
            s = "*" .. s .. "*"
        end
        texts[i] = s
    end
    return texts
end

-- The read-along texts: the word being read (and the one before, or its span) lit, other paragraphs dimmed
-- when the player has that on -- what addon.LitText does for one string, per block. Also notes where the word
-- sits (spokenY) for the auto-scroll.
local function LitSegTexts(index, span)
    local plain, tokens, spoken = frame.plain, frame.readTokens, frame.readSpoken
    local light = addon.ThemeIsLight()
    local code, dimCode = addon.HighlightCode(light), addon.FadeCode(light)
    local marks = {}
    for k = span and span[1] or math.max(1, index - 1), span and span[2] or index do
        if spoken[k] then marks[#marks + 1] = tokens[spoken[k]] end
    end
    local cur = spoken[index] and tokens[spoken[index]]
    local curPara
    frame.spokenY = nil
    if cur then
        for _, seg in ipairs(frame.segs) do
            if cur.s >= seg.a and cur.s <= seg.b then
                curPara = seg.para
                local frac = (cur.s - seg.da) / math.max(1, seg.db - seg.da + 1)
                frame.spokenY = (seg.top or 0) + math.max(0, frac) * (seg.h or 0)
                break
            end
        end
    end
    local texts = {}
    for i, seg in ipairs(frame.segs) do
        if #marks == 0 then
            local s = plain:sub(seg.da, seg.db)
            if seg.narr and s ~= "" then
                s = "*" .. s .. "*"
            end
            texts[i] = s
        else
            local dim = (dimCode and curPara and seg.para ~= curPara) and dimCode or nil
            texts[i] = SegText(plain, seg, marks, code, dim)
        end
    end
    return texts
end

-- Put the blocks in the scroll child, one font string each, stacked; returns the height they take.
local function LayoutSegments(texts)
    local child, width = frame.scrollChild, frame.textWidth or 1
    local line = frame.lineHeight or 15
    local y = 0
    for i, seg in ipairs(frame.segs) do
        local fs = frame.segFS[i]
        if not fs then
            fs = child:CreateFontString(nil, "ARTWORK")
            fs:SetJustifyH("LEFT")
            fs:SetJustifyV("TOP")
            fs:SetWordWrap(true)
            frame.segFS[i] = fs
        end
        local indent = seg.narr and NARR_INDENT or 0
        fs:SetFontObject(seg.narr and frame.narrFont or frame.textFont)
        fs:ClearAllPoints()
        fs:SetPoint("TOPLEFT", child, "TOPLEFT", indent, -y)
        fs:SetWidth(width - indent)
        fs:SetText(texts[i])
        fs:Show()
        seg.top = y
        seg.h = math.max(1, fs:GetStringHeight() or 1)
        y = y + seg.h
        local nextSeg = frame.segs[i + 1]
        if nextSeg then
            y = y + ((nextSeg.para ~= seg.para) and math.floor(line * 0.6 + 0.5) or 3)
        end
    end
    for i = #frame.segs + 1, #frame.segFS do
        frame.segFS[i]:SetText("")
        frame.segFS[i]:Hide()
    end
    return math.max(1, y)
end

-- New colours only (read-along): the words keep their places, so nothing moves.
local function SetSegTexts(texts)
    for i = 1, #frame.segs do
        frame.segFS[i]:SetText(texts[i])
    end
end

local function InFight()
    return (InCombatLockdown and InCombatLockdown()) or (UnitAffectingCombat and UnitAffectingCombat("player"))
end

local function Duration(sd)
    local duration = tonumber(sd.duration)
    if duration and duration > 0 then
        return duration
    end
    return nil
end

local function Elapsed(sd)
    if paused then
        return pausedElapsed
    end
    if not sd.startedAt then
        return 0
    end
    local elapsed = math.max(0, GetTime() - sd.startedAt)
    if sd.preview then
        elapsed = elapsed % sd.duration
    end
    return elapsed
end

local function Clock(seconds)
    seconds = math.max(0, math.floor(seconds))
    return string.format("%d:%02d", math.floor(seconds / 60), seconds % 60)
end

-- Whether the window the narration came from is still on screen, in which
-- case that window is already showing the text.
local function Shown(f)
    return f and f.IsShown and f:IsShown()
end

local function SourceWindowOpen(sd)
    if sd.preview then
        return false
    end
    if Shown(_G.ImmersionFrame) or Shown(_G.DUIQuestFrame) then
        return true
    end
    if sd.textType == "item" then
        return Shown(ItemTextFrame) or Shown(_G.DUIBookFrame)
    elseif sd.textType == "gossip" then
        return Shown(GossipFrame)
    end
    return Shown(QuestFrame) or (QuestMapFrame and QuestMapFrame:IsVisible())
end
addon.SourceWindowOpen = SourceWindowOpen

-- --------------------------------------------------------------------------
-- The frame
-- --------------------------------------------------------------------------

local function SavePosition()
    local point, _, relativePoint, x, y = frame:GetPoint(1)
    local scale = frame:GetScale()
    -- Stored in UIParent units, so changing the size keeps it in place.
    local db = DB()
    db.speechFramePos = { point, relativePoint, x * scale, y * scale }
end

local function ApplyPosition()
    local pos = DB().speechFramePos or DEFAULT_POINT
    local scale = SizeScale()
    frame:SetScale(scale)
    frame:ClearAllPoints()
    frame:SetPoint(pos[1], UIParent, pos[2], pos[3] / scale, pos[4] / scale)
end

-- The bar's controls are bare glyphs, not labelled buttons (owner, 2026-11-12: the buttons were "way too big" and
-- too close together; "a bit more translucent and literally just icons"). Each is drawn in the theme's ink, faint
-- until the mouse is on it, with a tooltip saying what it does.
-- The glyphs are drawn here from flat colour shapes -- the usual media symbols: play, pause bars, stop square,
-- back-to-start (bar + left triangle) for Replay, skip (right triangle + bar) for Next -- so they look the same in
-- every client and theme. The game's stopwatch art was tried first and showed as boxed buttons that did not read
-- (owner's screenshot, 2026-11-12: "the icons are hard to understand").
local ICON_SIZE = 18
local ICON_GAP = 12
local ICON_FAINT = 0.45

local iconButtons = {}

local function InkIcon(button)
    local theme = addon.Theme and addon.Theme()
    local ink = theme and theme.text or { 1, 1, 1 }
    for _, tex in ipairs(button.inked) do
        tex:SetColorTexture(ink[1], ink[2], ink[3], 1)
    end
end

-- A rectangle centred x across from the button's middle.
local function Rect(button, parts, width, height, x)
    local tex = button:CreateTexture(nil, "ARTWORK")
    tex:SetSize(width, height)
    tex:SetPoint("CENTER", button, "CENTER", x or 0, 0)
    button.inked[#button.inked + 1] = tex
    parts[#parts + 1] = tex
    return tex
end

-- A triangle as stacked one-pixel rows (each a little taller than its step, so no gaps at odd UI scales). Its flat
-- side stands at edgeX from the button's middle; it points "right" or "left" from there.
local function Triangle(button, parts, pointing, height, width, edgeX)
    local half = height / 2
    for row = 0, height - 1 do
        local mid = half - row - 0.5
        local w = math.max(1, width * (1 - math.abs(mid) / half))
        local tex = button:CreateTexture(nil, "ARTWORK")
        tex:SetSize(w, 1.5)
        if pointing == "right" then
            tex:SetPoint("LEFT", button, "CENTER", edgeX, mid)
        else
            tex:SetPoint("RIGHT", button, "CENTER", edgeX, mid)
        end
        button.inked[#button.inked + 1] = tex
        parts[#parts + 1] = tex
    end
end

local GLYPHS = {
    play = function(b, p) Triangle(b, p, "right", 12, 10, -4) end,
    pause = function(b, p) Rect(b, p, 3, 11, -3); Rect(b, p, 3, 11, 3) end,
    stop = function(b, p) Rect(b, p, 10, 10, 0) end,
    replay = function(b, p) Rect(b, p, 2, 11, -5); Triangle(b, p, "left", 11, 9, 6) end,
    next = function(b, p) Triangle(b, p, "right", 11, 9, -6); Rect(b, p, 2, 11, 5) end,
    -- Two left triangles (rewind), so it does not read as Replay's back-to-start.
    previous = function(b, p) Triangle(b, p, "left", 11, 7, 0); Triangle(b, p, "left", 11, 7, 7) end,
}
addon.SpeechFrameGlyphs = GLYPHS

local function IconButton(parent, glyph, onClick, tooltip)
    local button = CreateFrame("Button", nil, parent)
    button:SetSize(ICON_SIZE, ICON_SIZE)
    button.inked = {}
    button.glyphParts = {}
    -- Shows one glyph, drawing it the first time.
    function button:SetGlyph(name)
        if self.glyph == name then return end
        self.glyph = name
        if not self.glyphParts[name] and GLYPHS[name] then
            local parts = {}
            GLYPHS[name](self, parts)
            self.glyphParts[name] = parts
            InkIcon(self)
        end
        for key, parts in pairs(self.glyphParts) do
            for _, tex in ipairs(parts) do
                tex:SetShown(key == name)
            end
        end
    end
    if glyph then
        button:SetGlyph(glyph)
    end
    button:SetAlpha(ICON_FAINT)
    button:SetScript("OnEnter", function(self)
        self:SetAlpha(1)
        if self.tooltip then
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:AddLine(self.tooltip, 1, 1, 1, true)
            GameTooltip:Show()
        end
    end)
    button:SetScript("OnLeave", function(self)
        self:SetAlpha(ICON_FAINT)
        GameTooltip:Hide()
    end)
    button:SetScript("OnClick", onClick)
    button.tooltip = tooltip
    iconButtons[#iconButtons + 1] = button
    return button
end

-- What the line is, in the bottom left corner, faint (owner, 2026-11-12): the game's own quest marks, so a player
-- reads them at a glance -- ! a new quest, grey ? one still in progress, gold ? one being handed in -- a speech bubble
-- for gossip and an open book for books. The preview shows the ! as a sample; zone lore shows nothing.
-- 0.75: with no label the mark carries the meaning alone, and the grey ? all but vanished on parchment at 0.6
-- (owner's screenshot, 2026-11-12).
local KIND_FAINT = 0.75
local KINDS = {
    description = { tex = "Interface\\GossipFrame\\AvailableQuestIcon", tip = "New quest" },
    progress = { tex = "Interface\\GossipFrame\\ActiveQuestIcon", grey = true, tip = "Quest in progress" },
    completion = { tex = "Interface\\GossipFrame\\ActiveQuestIcon", tip = "Quest complete" },
    gossip = { tex = "Interface\\GossipFrame\\GossipGossipIcon", tip = "Gossip" },
    item = { tex = "Interface\\GossipFrame\\TrainerGossipIcon", tip = "Book" },
}
addon.SpeechFrameKinds = KINDS

local Pause, Resume, StopNarration, Replay, Dismiss, OpenMenu
local CaptureModel   -- defined with the moving head, used by SpeechFrameCapturePortrait above it

local function Build()
    if frame then
        return
    end

    frame = CreateFrame("Frame", "SpeakStoneSpeechFrame", UIParent)
    frame:SetSize(WIDTH, HEIGHT)
    frame:SetFrameStrata("MEDIUM")
    frame:SetClampedToScreen(true)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", function(self)
        if not DB().speechFrameLocked then
            self:StartMoving()
        end
    end)
    frame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        SavePosition()
    end)
    frame:SetScript("OnMouseUp", function(self, button)
        if button == "RightButton" then
            OpenMenu(self)
        end
    end)
    frame:Hide()

    -- A dark band fading out to the right, gold hairlines top and bottom.
    local band = frame:CreateTexture(nil, "BACKGROUND")
    band:SetAllPoints()
    frame.band = band
    local lineTop = frame:CreateTexture(nil, "BORDER")
    lineTop:SetPoint("TOPLEFT")
    lineTop:SetPoint("TOPRIGHT")
    lineTop:SetHeight(1)
    local lineBottom = frame:CreateTexture(nil, "BORDER")
    lineBottom:SetPoint("BOTTOMLEFT")
    lineBottom:SetPoint("BOTTOMRIGHT")
    lineBottom:SetHeight(1)
    frame.lineTop, frame.lineBottom = lineTop, lineBottom

    -- The portrait's square: pinned to the top (same spot as centred at the
    -- base height), so the text below stays inside the frame when "show all
    -- the text" grows it. Everything the portrait draws sits in it.
    frame.portraitArea = CreateFrame("Frame", nil, frame)
    frame.portraitArea:SetSize(PORTRAIT, PORTRAIT)
    frame.portraitArea:SetPoint("TOPLEFT", frame, "TOPLEFT", 12, -(HEIGHT - PORTRAIT) / 2)

    -- The still picture (speechPortrait3D off, or no model to show): the
    -- game draws it on black, which cannot be taken out, so it sits a little
    -- inside a thin ring in the theme's colour with a soft halo round that
    -- (owner, 2026-11-07).
    local function Disc(layer, sub, size)
        local t = frame:CreateTexture(nil, layer, nil, sub)
        t:SetSize(size, size)
        t:SetPoint("CENTER", frame.portraitArea, "CENTER")
        local m = frame:CreateMaskTexture()
        m:SetTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
        m:SetAllPoints(t)
        t:AddMaskTexture(m)
        return t, m
    end
    frame.ringHalo = Disc("BORDER", 0, PORTRAIT + 4)
    frame.ring = Disc("BORDER", 1, PORTRAIT - 2)
    local mask
    frame.portrait, mask = Disc("ARTWORK", 0, PORTRAIT - 6)
    frame.portraitMask = mask

    -- The moving head (speechPortrait3D, the default): the NPC's own model,
    -- framed on its face, nothing behind it, so the bar shows through; it
    -- talks sentence by sentence with the voice (UpdateTalk).
    -- frame.model is the one on screen: frame.baseModel, or a line's own captured model (CaptureModel).
    frame.NewModel = function()
        local m = CreateFrame("PlayerModel", nil, frame.portraitArea)
        m:SetAllPoints(frame.portraitArea)
        m:Hide()
        -- Some animations play once: a talk that ends mid-sentence starts again.
        m:SetScript("OnAnimFinished", function(self)
            if self.talkAnim then
                self:SetAnimation(self.talkAnim)
            end
        end)
        -- The camera is set again once the model has loaded: set before that, the
        -- game frames the whole body (owner, 2026-11-07: "zoom in on the face").
        m:SetScript("OnModelLoaded", function(self)
            if frame.ApplyFace then frame.ApplyFace(self) end
        end)
        return m
    end
    frame.baseModel = frame.NewModel()
    frame.model = frame.baseModel

    -- Close: a bare X in the theme's ink, faint like the other icons (was a boxed "X" button, and before that
    -- Blizzard's red-and-gold one).
    frame.close = IconButton(frame, nil, function() Dismiss() end, "Close. The voice carries on.")
    frame.close:SetSize(14, 14)
    frame.close:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -10, -10)
    local crossParts = {}
    for _, angle in ipairs({ 45, -45 }) do
        -- 3 px, to match the weight of the solid play / pause / stop shapes.
        local bar = Rect(frame.close, crossParts, 15, 3, 0)
        if bar.SetRotation then bar:SetRotation(math.rad(angle)) end
    end
    InkIcon(frame.close)

    -- Controls, right to left from the close button.
    local controls = CreateFrame("Frame", nil, frame)
    controls:SetSize(1, ICON_SIZE)
    controls:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -36, -8)
    frame.controls = controls
    controls.gear = CreateFrame("Button", nil, controls)
    controls.gear:SetSize(18, 18)
    controls.gear:SetPoint("RIGHT", controls, "RIGHT", 0, 0)
    controls.gear:SetNormalTexture("Interface\\WorldMap\\Gear_64Grey")
    controls.gear:SetHighlightTexture("Interface\\WorldMap\\Gear_64Grey", "ADD")
    controls.gear:SetScript("OnClick", function(self) OpenMenu(self) end)
    -- Faint and grey like the other icons until the mouse is on it (owner, 2026-11-12: "a little more
    -- translucent and faded").
    local function QuietGear(self, on)
        local tex = self:GetNormalTexture()
        if tex then tex:SetDesaturated(not on) end
        self:SetAlpha(on and 1 or ICON_FAINT * 0.8)
    end
    QuietGear(controls.gear, false)
    controls.gear:SetScript("OnEnter", function(self)
        QuietGear(self, true)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine("Size and position", 1, 1, 1)
        GameTooltip:AddLine("Also right-click the frame.", 0.7, 0.7, 0.7)
        GameTooltip:Show()
    end)
    controls.gear:SetScript("OnLeave", function(self)
        QuietGear(self, false)
        GameTooltip:Hide()
    end)
    controls.time = controls:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    controls.time:SetPoint("RIGHT", controls.gear, "LEFT", -8, 0)
    -- Report: a faded warning sign that opens the report menu for the line
    -- being read (owner, 2026-11-07: in place of the favourite star, which
    -- the Guide still has). The same sign as the flag on Dialogue UI's window.
    controls.star = CreateFrame("Button", nil, controls)
    controls.star:SetSize(16, 16)
    controls.star:SetPoint("RIGHT", controls.time, "LEFT", -8, 0)
    controls.star:SetNormalTexture("Interface\\DialogFrame\\UI-Dialog-Icon-AlertNew")
    -- Grey and faint until the mouse is on it, so it does not stand out (owner, 2026-11-07).
    local function Quiet(self, on)
        local tex = self:GetNormalTexture()
        if tex then tex:SetDesaturated(not on) end
        self:SetAlpha(on and 1 or 0.3)
    end
    Quiet(controls.star, false)
    controls.star:SetScript("OnClick", function(self)
        if current and addon.OpenReportMenu then
            addon.OpenReportMenu(self, current)
        end
    end)
    controls.star:SetScript("OnEnter", function(self)
        Quiet(self, true)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine("Report this voice line", 1, 0.82, 0)
        GameTooltip:AddLine("Wrong voice, audio glitch, pronunciation, text that doesn't match: click to pick what is wrong. It goes into your capture export.", 1, 1, 1, true)
        GameTooltip:Show()
    end)
    controls.star:SetScript("OnLeave", function(self)
        Quiet(self, false)
        GameTooltip:Hide()
    end)
    -- Icons, spaced apart (owner, 2026-11-12), in the old order: Next, Pause, Stop, Replay.
    controls.replay = IconButton(controls, "replay", function() Replay() end, "Replay: hear the line again from the start.")
    controls.replay:SetPoint("RIGHT", controls.star, "LEFT", -ICON_GAP, 0)
    controls.stop = IconButton(controls, "stop", function() StopNarration() end, "Stop the narration and close.")
    controls.stop:SetPoint("RIGHT", controls.replay, "LEFT", -ICON_GAP, 0)
    controls.pause = IconButton(controls, "pause", function()
        if paused then Resume() else Pause() end
    end)
    controls.pause:SetPoint("RIGHT", controls.stop, "LEFT", -ICON_GAP, 0)
    controls.next = IconButton(controls, "next", function()
        paused = false
        lingerUntil = nil
        if addon.PlayNextQueued then addon.PlayNextQueued() end
    end, "Next: skip to the next queued quest.")
    controls.next:SetPoint("RIGHT", controls.pause, "LEFT", -ICON_GAP, 0)
    controls.next:Hide()
    -- Previous (2026-11-23 prototype): the queued line before this one, from the top. Placed left of Next, or of
    -- Pause when nothing is left to skip to (Tick moves it).
    controls.previous = IconButton(controls, "previous", function()
        paused = false
        lingerUntil = nil
        if addon.PlayPreviousQueued then addon.PlayPreviousQueued() end
    end, "Previous: hear the queued line before this one again.")
    controls.previous:SetPoint("RIGHT", controls.pause, "LEFT", -ICON_GAP, 0)
    controls.previous:Hide()
    -- No Report button here any more: the warning sign beside Replay does the same (owner, 2026-11-07: "we have
    -- two"). showReportButton now only puts one on Blizzard's quest window.

    frame.name = frame:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    -- Its own row under the buttons, full width, so the quest title is not
    -- cut short by Pause/Stop/Replay/Next.
    frame.name:SetPoint("LEFT", frame.portraitArea, "RIGHT", 14, 0)
    frame.name:SetPoint("TOP", frame, "TOP", 0, -32)
    frame.name:SetJustifyH("LEFT")
    frame.name:SetWordWrap(false)
    -- The quest title (or a book's page) on its own, smaller and in the theme's quieter colour, sitting on the
    -- name's baseline: one string in two colours at one size made the NPC and the quest hard to tell apart
    -- (owner, 2026-11-12). It takes what width the name leaves and is cut short first.
    frame.subtitle = frame:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    frame.subtitle:SetPoint("BOTTOMLEFT", frame.name, "BOTTOMRIGHT", 10, 1)
    frame.subtitle:SetPoint("RIGHT", frame, "RIGHT", -16, 0)
    frame.subtitle:SetJustifyH("LEFT")
    frame.subtitle:SetWordWrap(false)

    -- The text, whole, in a mouse-wheel scroll area TEXT_LINES tall.
    local textFont = CreateFont("SpeakStoneSpeechTextFont")
    textFont:CopyFontObject(GameFontHighlight)
    frame.textFont = textFont
    local lineHeight = 13 + 2

    local scroll = CreateFrame("ScrollFrame", nil, frame)
    scroll:SetPoint("TOPLEFT", frame.name, "BOTTOMLEFT", 0, -6)
    scroll:SetPoint("RIGHT", frame, "RIGHT", -16, 0)
    scroll:SetHeight(lineHeight * TEXT_LINES)
    frame.lineHeight = lineHeight
    scroll:EnableMouseWheel(true)
    scroll:SetScript("OnMouseWheel", function(self, delta)
        -- A manual scroll pauses the auto-scroll for a few seconds.
        frame.manualScrollUntil = GetTime() + 4
        local target = (frame.scrollTarget or self:GetVerticalScroll()) - delta * frame.lineHeight * 2
        frame.scrollTarget = math.max(0, math.min(target, self:GetVerticalScrollRange()))
    end)
    -- Every frame, glide toward scrollTarget instead of jumping there: the text rolls up smoothly as it is read.
    scroll:SetScript("OnUpdate", function(self, elapsed)
        UpdateFades(self)
        local target = frame.scrollTarget
        if not target then return end
        local now = self:GetVerticalScroll()
        local diff = target - now
        if math.abs(diff) < 0.3 then
            if diff ~= 0 then self:SetVerticalScroll(target) end
            return
        end
        self:SetVerticalScroll(now + diff * math.min(1, elapsed * SCROLL_EASE))
    end)
    local child = CreateFrame("Frame", nil, scroll)
    child:SetSize(1, 1)
    scroll:SetScrollChild(child)
    frame.scroll = scroll
    frame.scrollChild = child

    -- Soft top and bottom edges (owner, 2026-11-19: "the top and bottom slightly fade with the text being
    -- read in the middle"). A frame above the scroll area holds two strips in the bar's own colour, see-through
    -- toward the middle; each shows only while there is text hidden past its edge (UpdateFades).
    local fades = CreateFrame("Frame", nil, frame)
    fades:SetAllPoints(scroll)
    if fades.SetFrameLevel and scroll.GetFrameLevel then
        fades:SetFrameLevel(scroll:GetFrameLevel() + 5)
    end
    for _, key in ipairs({ "top", "bottom" }) do
        local edge = CreateFrame("Frame", nil, fades)
        edge:SetPoint(key == "top" and "TOPLEFT" or "BOTTOMLEFT")
        edge:SetPoint(key == "top" and "TOPRIGHT" or "BOTTOMRIGHT")
        edge:SetHeight(1)
        edge:SetAlpha(0)
        edge.strips = {}
        for i = 1, FADE_STRIPS do
            edge.strips[i] = edge:CreateTexture(nil, "OVERLAY")
        end
        fades[key] = edge
    end
    frame.fades = fades

    frame.text = child:CreateFontString(nil, "ARTWORK")
    frame.text:SetFontObject(textFont)
    frame.text:SetPoint("TOPLEFT")
    frame.text:SetJustifyH("LEFT")
    frame.text:SetJustifyV("TOP")
    frame.text:SetWordWrap(true)
    frame.segFS = { frame.text }
    -- Narrator parts: a size smaller, in the quieter ink (SpeechFrameApplyFont / SpeechFramePaint).
    local narrFont = CreateFont("SpeakStoneSpeechNarratorFont")
    narrFont:CopyFontObject(textFont)
    frame.narrFont = narrFont

    frame.measure = frame:CreateFontString(nil, "ARTWORK")
    frame.measure:SetFontObject(textFont)
    frame.measure:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
    frame.measure:SetAlpha(0)
    frame.measure:Hide()
    frame.measure.ssRole = false
    addon.SpeechFrameApplyFont()

    frame.progress = CreateFrame("StatusBar", nil, frame)
    frame.progress:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
    frame.progress:SetHeight(2)
    frame.progress:SetMinMaxValues(0, 1)
    frame.progress:SetPoint("TOPLEFT", scroll, "BOTTOMLEFT", 0, -4)
    frame.progress:SetPoint("RIGHT", scroll, "RIGHT", 0, 0)
    frame.track = frame.progress:CreateTexture(nil, "BACKGROUND")
    frame.track:SetAllPoints()

    -- What kind of line this is: the mark alone, faint in the bottom left corner under the portrait (KINDS;
    -- owner, 2026-11-12: moved from the bottom right, then "remove the text and just use the icons"). What it
    -- means is in its tooltip.
    frame.kind = CreateFrame("Frame", nil, frame)
    frame.kind:SetSize(16, 16)
    -- On the progress bar's row (it sat ~10 px below it), at the frame's left edge like the portrait.
    frame.kind:SetPoint("RIGHT", frame.progress, "LEFT", -(14 + PORTRAIT - 16), 0)
    frame.kind:SetAlpha(KIND_FAINT)
    frame.kind:EnableMouse(true)
    frame.kind.icon = frame.kind:CreateTexture(nil, "ARTWORK")
    frame.kind.icon:SetAllPoints()
    frame.kind:SetScript("OnEnter", function(self)
        self:SetAlpha(1)
        if self.tip then
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:AddLine(self.tip, 1, 1, 1)
            GameTooltip:Show()
        end
    end)
    frame.kind:SetScript("OnLeave", function(self)
        self:SetAlpha(KIND_FAINT)
        GameTooltip:Hide()
    end)
    frame.kind:Hide()

    ApplyPosition()
    addon.SpeechFramePaint()
end

-- The reading font (Fonts.lua) on the text, and the row height measured from it.
function addon.SpeechFrameApplyFont()
    if not frame or not frame.textFont then
        return
    end
    local add = TextAdd()
    local custom = addon.ApplyReadingFont and addon.ApplyReadingFont(frame.textFont, 12 + add, "")
    if not custom then
        frame.textFont:SetFont((GameFontHighlight:GetFont()), 13 + add, "")
    end
    local spacing = custom and 4 or 2
    frame.textFont:SetSpacing(spacing)
    if frame.narrFont then
        local italic = addon.NarratorItalicFontPath and addon.NarratorItalicFontPath()
        if italic then
            frame.narrFont:SetFont(italic, 12 + add - 1, "")
        else
            local smaller = addon.ApplyReadingFont and addon.ApplyReadingFont(frame.narrFont, 12 + add - 2, "")
            if not smaller then
                frame.narrFont:SetFont((GameFontHighlight:GetFont()), 13 + add - 2, "")
            end
        end
        frame.narrFont:SetSpacing(spacing)
    end
    frame.measure:Show()
    frame.measure:SetText("A")
    local one = frame.measure:GetStringHeight() or 0
    frame.measure:SetText("A\nA")
    local two = frame.measure:GetStringHeight() or 0
    frame.measure:SetText("")
    frame.measure:Hide()
    frame.lineHeight = (two - one > 4) and (two - one) or ((custom and 12 or 13) + add + spacing)
    frame.scroll:SetHeight(frame.lineHeight * Lines())
    frame.filledFor = nil
end

-- Colours and background from the chosen theme (Theme.lua).
function addon.SpeechFramePaint()
    if not frame then
        return
    end
    local theme = addon.Theme()
    local art = addon.ThemeSlice(frame, "bar")
    frame.band:SetShown(not art)
    addon.ThemeBackground(frame.band, true)
    frame.lineTop:SetColorTexture(theme.line[1], theme.line[2], theme.line[3], theme.line[4])
    frame.lineBottom:SetColorTexture(theme.line[1], theme.line[2], theme.line[3], theme.line[4] * 0.6)
    frame.name:SetTextColor(unpack(theme.title))
    frame.textFont:SetTextColor(unpack(theme.text))
    -- The game's drop shadow behind dark ink on paper reads as bold: off on the light theme.
    frame.textFont:SetShadowColor(0, 0, 0, theme.light and 0 or 1)
    frame.textFont:SetShadowOffset(theme.light and 0 or 1, theme.light and 0 or -1)
    if frame.narrFont then
        frame.narrFont:SetTextColor(unpack(theme.sub))
        frame.narrFont:SetShadowColor(0, 0, 0, theme.light and 0 or 1)
        frame.narrFont:SetShadowOffset(theme.light and 0 or 1, theme.light and 0 or -1)
    end
    addon.ThemeShadow(frame.name)
    addon.ThemeShadow(frame.subtitle)
    frame.subtitle:SetTextColor(unpack(theme.sub))
    addon.ThemeShadow(frame.controls.time)
    frame.controls.time:SetTextColor(unpack(theme.sub))
    frame.progress:SetStatusBarColor(theme.accent[1], theme.accent[2], theme.accent[3], 0.9)
    frame.track:SetColorTexture(unpack(theme.track))
    -- The still picture's thin ring and its soft halo, in the theme's accent.
    frame.ring:SetColorTexture(theme.accent[1], theme.accent[2], theme.accent[3], 1)
    frame.ringHalo:SetColorTexture(theme.accent[1], theme.accent[2], theme.accent[3], 0.25)
    for _, button in ipairs(iconButtons) do
        InkIcon(button)
    end
    PaintFades(theme, art)
    frame.filledFor = nil         -- the header carries the theme's colour for the title
end
if addon.ThemeRegister then
    addon.ThemeRegister(function() addon.SpeechFramePaint() end)
end

-- A queued quest line starts after the player may have walked away, when
-- "npc" no longer exists. Its portrait is rendered into a texture of its own
-- at queue time (the NPC is still there) and swapped in when it plays.
local function HideCapturedPortraits()
    for _, tex in ipairs(frame.captured or {}) do
        tex:Hide()
    end
end

local function LineStillHeld(owner)
    if owner == addon.activeSound or owner == current then return true end
    if addon.pausedSound and addon.pausedSound.sd == owner then return true end
    for _, list in ipairs({ addon.speechQueue or {}, addon.speechHistory or {} }) do
        for _, sd in ipairs(list) do
            if sd == owner then return true end
        end
    end
    return false
end

function addon.SpeechFrameCapturePortrait(sd)
    if not sd or not sd.npcGUID or sd.portraitTex or not UnitExists("npc") then
        return
    end
    Build()
    local ok, same = pcall(function() return UnitGUID("npc") == sd.npcGUID end)
    if not ok or not same then
        return
    end
    frame.captured = frame.captured or {}
    local tex
    for _, t in ipairs(frame.captured) do
        -- Not one a line in the history or the paused line still shows (Previous / Resume bring those back).
        if not t.owner or not LineStillHeld(t.owner) then
            tex = t
            break
        end
    end
    if not tex then
        tex = frame:CreateTexture(nil, "ARTWORK")
        tex:SetAllPoints(frame.portrait)
        tex:AddMaskTexture(frame.portraitMask)
        table.insert(frame.captured, tex)
    end
    if tex.owner then
        tex.owner.portraitTex = nil
    end
    -- The moving head too, while the NPC is still here to load it from.
    CaptureModel(sd)
    tex:Hide()
    if pcall(SetPortraitTexture, tex, "npc") then
        tex.owner = sd
        sd.portraitTex = tex
    end
end

-- --------------------------------------------------------------------------
-- The moving head (speechPortrait3D, on by default; owner, 2026-11-07)
-- --------------------------------------------------------------------------
-- The NPC's model in a PlayerModel: SetUnit("npc") while it is still the one
-- the player is talking to (its exact look), else SetCreature by the ID in its
-- GUID (the speech frame mostly shows after the player has walked away).
-- Nothing to load (books, narrator lines, game objects) or a model that never
-- arrives: the still picture instead.
-- One talk for every sentence: the question (65) and exclamation (64) talks
-- wave the arms about, and with the camera on the face the plain talk reads as
-- the mouth and head moving (owner, 2026-11-07: "just see its face moving").
local TALK, STAND = 60, 0
local MODEL_GRACE = 1.0        -- seconds a model gets to load before the still picture takes over
local SENTENCE_REST = 0.3      -- seconds still at the end of each sentence but the last
-- The face framing: the portrait zoom (SetPortraitZoom(1), as 3D unit-frame portraits do), which aims at the model's
-- own face whatever its height, at its natural distance, with nothing moved. Tried and dropped on 2026-11-07 (owner's
-- screenshots): a fixed up/down offset in model units (right for one NPC's height, wrong for the next), a closer
-- default distance of 0.8 (cut off the top of the head), and SetCamera(0) (it framed the middle of the whole body).
-- speechHeadZoom scales the distance (1 = natural, under 1 = closer); /ss face <zoom> tunes it live. The default,
-- 1.35, is the owner's pick in game (2026-11-07: 1.1 first, then the crown was cut off on Gornek; 1.35 frames the
-- whole head). A screen-space shift down (SetViewTranslation) was tried for that and did nothing in game: removed.
local HEAD_ZOOM = 1.35

local function ApplyFace(m)
    pcall(m.SetPosition, m, 0, 0, 0)
    pcall(m.SetPortraitZoom, m, 1)
    pcall(m.SetCamDistanceScale, m, tonumber(DB().speechHeadZoom) or HEAD_ZOOM)
end
-- The tutorial's moving-head example frames the player's head the same way, so it looks as it will in play.
addon.ApplySpeakerFace = ApplyFace

-- /ss face [zoom]: how close the head is; shown on the head on screen now.
function addon.SpeechFrameFace(zoom)
    local db = DB()
    if zoom then db.speechHeadZoom = zoom end
    if frame and frame.model and frame.model:IsShown() then
        ApplyFace(frame.model)
    end
    return tonumber(db.speechHeadZoom) or HEAD_ZOOM
end

-- A line's own model, loaded from the NPC while the player is still talking to it (SetUnit: its exact look) and kept
-- for when the line plays later -- queued, replayed, or reached with Previous. Without it the bar fell back to
-- SetCreature(ID), which for some NPCs gives a different look every time: Chana (female Amani troll, one display)
-- showed as a red-haired male troll, then a yellow-haired one (owner's screenshots, 2026-11-23).
-- A model is reused once its line is gone from the current, queued and heard lines.
function CaptureModel(sd)
    if not (frame and sd and sd.npcGUID) or sd.preview or sd.textType == "item" or DB().speechPortrait3D ~= true then
        return nil
    end
    if sd.modelFrame and sd.modelFrame.owner == sd then
        return sd.modelFrame
    end
    local ok, same = pcall(function() return UnitExists("npc") and UnitGUID("npc") == sd.npcGUID end)
    if not ok or not same then
        return nil
    end
    frame.lineModels = frame.lineModels or {}
    local m
    for _, candidate in ipairs(frame.lineModels) do
        if not candidate.owner or not LineStillHeld(candidate.owner) then
            m = candidate
            break
        end
    end
    if not m then
        m = frame.NewModel()
        table.insert(frame.lineModels, m)
    end
    if m.owner and m.owner.modelFrame == m then
        m.owner.modelFrame = nil
    end
    if not pcall(function() m:ClearModel(); m:SetUnit("npc") end) then
        return nil
    end
    m:Hide()
    m.owner = sd
    sd.modelFrame = m
    return m
end
addon.SpeechFrameCaptureModel = CaptureModel

local function ShowModel(sd)
    -- The preview (/ss frame) shows the player's own head, so /ss face can be tried anywhere.
    -- Only when chosen: the still picture is the default (owner, 2026-11-07).
    if not (frame.baseModel and sd and (sd.npcGUID or sd.preview)) or sd.textType == "item" or DB().speechPortrait3D ~= true then
        return false
    end
    -- The line's own model when it has one (or can take one now); the shared one otherwise.
    local own = CaptureModel(sd)
    -- /ssdebug: which creature the head comes from, and how (a follower or a troll standing nearby being the
    -- quest window's "npc" would show here as an ID that is not the speaker's).
    if addon.DebugPrint and not sd.preview then
        local id = addon.CreatureIDFromGUID and sd.npcGUID and addon.CreatureIDFromGUID(sd.npcGUID)
        addon.DebugPrint(("SpeakStone head: %s, creature %s, %s"):format(tostring(sd.npcName), tostring(id),
            own and "captured from the NPC" or ((UnitExists("npc") and UnitGUID("npc") == sd.npcGUID)
                and "from the NPC now" or "rebuilt from the creature ID")))
    end
    for _, other in ipairs(frame.lineModels or {}) do
        if other ~= own then other:Hide() end
    end
    frame.baseModel:Hide()
    if own then
        frame.model = own
        frame.ApplyFace = ApplyFace
        ApplyFace(own)
        own.talkAnim, own.plan, own.planFor, own.current = nil, nil, nil, nil
        own.shownAt = GetTime()
        own:Show()
        return true
    end
    local m = frame.baseModel
    frame.model = m
    local shown = false
    pcall(function()
        m:ClearModel()
        if sd.preview then
            m:SetUnit("player")
            shown = true
        elseif UnitExists("npc") and UnitGUID("npc") == sd.npcGUID then
            m:SetUnit("npc")
            shown = true
        elseif m.SetCreature and addon.CreatureIDFromGUID then
            local id = addon.CreatureIDFromGUID(sd.npcGUID)
            if id then
                m:SetCreature(id)
                shown = true
            end
        end
    end)
    if not shown then
        return false
    end
    frame.ApplyFace = ApplyFace
    ApplyFace(m)
    m.talkAnim, m.plan, m.planFor, m.current = nil, nil, nil, nil
    m.shownAt = GetTime()
    m:Show()
    return true
end

-- When each sentence of the line is spoken (the pack's sentence timings when it
-- has them, the word estimate otherwise). A sentence that is a stage direction
-- the narrator reads leaves the NPC still.
function addon.SpeechTalkPlan(text, duration, soundFile)
    if not (addon.SubtitleWords and addon.SubtitleTiming and duration and duration > 0) then
        return nil
    end
    local narrated = addon.ClipNarrated and addon.ClipNarrated(soundFile)
    local words = addon.SubtitleWords(text or "", narrated)
    if #words == 0 then
        return nil
    end
    local times, starts = addon.SubtitleTiming(words, duration, soundFile)
    starts = starts or addon.SubtitleSentences(words)
    local plan = {}
    for s, first in ipairs(starts) do
        local nextFirst = starts[s + 1]
        plan[#plan + 1] = {
            from = times[first] or 0,
            to = nextFirst and times[nextFirst] or duration,
            anim = TALK,
            quiet = narrated and words[first]:sub(1, 1) == "<",
            -- The breath between sentences: the head stops for it, so it follows the voice line by line.
            rest = nextFirst and SENTENCE_REST or 0,
        }
    end
    return plan
end

-- The talk to play at `elapsed` seconds into the line: an animation ID, or STAND.
function addon.SpeechTalkAt(plan, elapsed)
    for _, p in ipairs(plan or {}) do
        if elapsed >= p.from and elapsed < p.to then
            if p.quiet or elapsed >= p.to - p.rest then
                return STAND
            end
            return p.anim
        end
    end
    return STAND
end

local function UpdateTalk(sd, elapsed, duration, playing)
    local m = frame.model
    if not (m and m:IsShown()) then
        return
    end
    -- A model that never loaded (an NPC the client has no data for): the still picture.
    if m.GetModelFileID and GetTime() - (m.shownAt or 0) > MODEL_GRACE then
        local ok, file = pcall(m.GetModelFileID, m)
        if ok and (not file or file == 0) then
            m:Hide()
            if frame.ShowStill then frame.ShowStill(sd) end
            return
        end
    end
    if not m.SetAnimation then
        return
    end
    if m.planFor ~= sd then
        m.plan, m.planFor = addon.SpeechTalkPlan(sd.text, duration, sd.soundFile), sd
    end
    local want = (playing and m.plan) and addon.SpeechTalkAt(m.plan, elapsed) or STAND
    if want ~= m.current then
        m.current = want
        m.talkAnim = want ~= STAND and want or nil
        pcall(m.SetAnimation, m, want)
    end
end

local function ShowStill(sd)
    frame.ring:Show()
    frame.ringHalo:Show()
    HideCapturedPortraits()
    frame.portrait:Show()
    if sd.portraitTex and sd.portraitTex.owner == sd then
        frame.portrait:Hide()
        sd.portraitTex:Show()
        return
    end
    local done = false
    if sd.npcGUID and UnitExists("npc") then
        pcall(function()
            if UnitGUID("npc") == sd.npcGUID then
                SetPortraitTexture(frame.portrait, "npc")
                done = true
            end
        end)
    end
    if not done then
        frame.portrait:SetTexture(sd.textType == "item" and "Interface\\Icons\\INV_Misc_Book_09"
            or "Interface\\Icons\\INV_Misc_Note_01")
    end
end

-- The moving head when there is one to show, else the still picture in its ring.
local function SetPortrait(sd)
    frame.ShowStill = ShowStill
    if ShowModel(sd) then
        HideCapturedPortraits()
        frame.portrait:Hide()
        frame.ring:Hide()
        frame.ringHalo:Hide()
        return
    end
    frame.model:Hide()
    for _, other in ipairs(frame.lineModels or {}) do
        other:Hide()
    end
    ShowStill(sd)
end

-- The setting changed: show the clip on screen the new way.
function addon.SpeechFrameRefreshPortrait()
    if frame and current then
        SetPortrait(current)
    end
end

-- Who is speaking, and the quest (a book: its title, then the page), shown apart.
local function HeaderParts(sd)
    local name = Readable(sd.npcName)
    local title = Readable(sd.title)
    if sd.textType == "item" then
        name, title = title or "Book", sd.page and ("Page " .. sd.page) or nil
    end
    name = name or title or "SpeakStone"
    if title == name then
        title = nil
    end
    return name, title
end
addon.SpeechFrameHeaderParts = HeaderParts

-- The report sign (it took the favourite star's place and name): shown for a
-- real clip, hidden for the preview, which has nothing to report.
function addon.SpeechFrameRefreshStar()
    if not frame or not frame.controls.star then return end
    frame.controls.star:SetShown(current ~= nil and not current.preview and current.soundFile ~= nil)
end

-- Text and header, once per clip.
local function Fill(sd)
    local name, title = HeaderParts(sd)
    -- Unbounded before measuring: GetStringWidth is capped by the width the last line set, so a long name after a
    -- short one ("Bob", then "Archmage Khadgar") came out as "Ar...".
    frame.name:SetWidth(0)
    frame.name:SetText(name)
    frame.subtitle:SetText(title or "")
    -- The name keeps at most 60% of the row, so a long name still leaves the quest some room.
    local row = WIDTH - PORTRAIT - 12 - 14 - 16
    local natural = frame.name:GetStringWidth() or 0
    frame.name:SetWidth(natural > 0 and math.min(natural + 2, row * (title and 0.6 or 1)) or row * 0.6)
    local text = Readable(sd.text)
    if text then
        text = text:gsub("\r", ""):gsub("\n%s*\n+", "\n\n")
    else
        text = "|cff9d9d9d(No text for this line.)|r"
    end
    local width = frame.scroll:GetWidth()
    if not width or width <= 0 then
        width = WIDTH - PORTRAIT - 12 - 14 - 16
    end
    frame.textWidth = width
    frame.plain, frame.litIndex, frame.readKey, frame.spokenY = text, nil, nil, nil
    frame.segs = Segments(text)
    local textHeight = LayoutSegments(PlainSegTexts())
    frame.textHeight = textHeight
    -- Fixed lines, or grown to fit the whole text (capped); never grown when compact.
    local lines = Lines()
    if DB().speechFitText and not Compact() then
        lines = math.max(lines, math.min(MAX_FIT_LINES, math.ceil(textHeight / frame.lineHeight)))
    end
    local scrollHeight = frame.lineHeight * lines
    frame.scroll:SetHeight(scrollHeight)
    -- Room under the text, when it does not all fit, so the last sentence can roll up to the middle like the
    -- rest instead of stopping at the bottom edge (owner, 2026-11-19).
    local pad = 0
    if textHeight > scrollHeight then
        pad = math.max(0, math.floor(scrollHeight / 2 - frame.lineHeight / 2 + 0.5))
    end
    frame.scrollChild:SetSize(width, textHeight + pad)
    -- Never shorter than the portrait needs.
    frame:SetHeight(math.max(HEIGHT - BASE_LINE, HEIGHT + scrollHeight - BASE_LINE * TEXT_LINES))
    frame.scroll:SetVerticalScroll(0)
    frame.scrollTarget = 0
    frame.filledFor = sd
    addon.SpeechFrameRefreshStar()
    local kind = KINDS[sd.preview and "description" or sd.textType or ""]
    if kind then
        frame.kind.icon:SetTexture(kind.tex)
        frame.kind.icon:SetDesaturated(kind.grey == true)
        frame.kind.tip = kind.tip
        frame.kind:Show()
    else
        frame.kind:Hide()
    end
end

local function Refresh()
    local sd = current
    if frame.filledFor ~= sd then
        Fill(sd)
    end
    local elapsed = Elapsed(sd)
    local duration = Duration(sd)
    -- The moving head talks while the voice does, sentence by sentence; still when paused or done.
    UpdateTalk(sd, elapsed, duration, duration ~= nil and not paused and sd.isPlaying == true)
    -- Read along: the word being spoken lit in the text, when the player has that on.
    if frame.plain and addon.ReadTokens then
        local playing = duration and not paused and sd.isPlaying and (DB().subtitleHighlight ~= false)
            and not frame.plain:find("|", 1, true)
        if playing then
            local key = frame.plain .. "#" .. duration
            if frame.readKey ~= key then
                frame.readKey = key
                frame.readTokens, frame.readSpoken, frame.readWords = addon.ReadTokens(frame.plain,
                    addon.ClipNarrated and addon.ClipNarrated(sd.soundFile))
                frame.readTimes, frame.readStarts = addon.SubtitleTiming(frame.readWords, duration, sd.soundFile)
                frame.litIndex = nil
            end
            local index = elapsed >= duration and 0 or addon.SubtitleWordAt(frame.readTimes, elapsed + 0.12)
            local span = addon.SubtitleSpan(frame.readStarts, index, frame.readWords, true)
            local litKey = index .. (span and (":" .. span[1]) or "")
            if frame.litIndex ~= litKey then
                frame.litIndex = litKey
                -- Also notes where the spoken word sits (spokenY), so the auto-scroll below follows the
                -- voice's real pace (sentence timings) instead of assuming words spread evenly over the clip.
                SetSegTexts(LitSegTexts(index, span))
            end
        elseif frame.litIndex then
            frame.litIndex = nil
            frame.spokenY = nil
            SetSegTexts(PlainSegTexts())
        end
    end
    if duration then
        local fraction = math.min(1, elapsed / duration)
        frame.progress:SetValue(fraction)
        -- Auto-scroll: keep the line being spoken (estimated from how far
        -- through the clip we are) in the middle of the text area.
        local range = frame.scroll:GetVerticalScrollRange()
        if range > 0 and not paused and DB().speechAutoScroll ~= false and GetTime() >= (frame.manualScrollUntil or 0) then
            -- The spoken line sits in the middle, between the soft top and bottom edges (owner, 2026-11-19);
            -- the OnUpdate above glides there. The read-along word's place in the text when there is one,
            -- else how far through the clip we are.
            local y = frame.spokenY or fraction * (frame.textHeight or frame.scrollChild:GetHeight())
            local target = y - frame.scroll:GetHeight() / 2 + (frame.lineHeight or 0) / 2
            -- Whole lines only, so no line is shown cut in half at the top or bottom -- except in compact
            -- mode, where the text rolls up continuously with the voice instead of stepping a line at a time
            -- (owner, 2026-11-19: "make it scroll through smoothly").
            if not Compact() then
                local step = frame.lineHeight or 1
                target = math.floor(target / step + 0.5) * step
            end
            frame.scrollTarget = math.max(0, math.min(target, range))
        end
        frame.controls.time:SetText(Clock(math.min(elapsed, duration)) .. " / " .. Clock(duration))
    else
        frame.progress:SetValue(0)
        frame.controls.time:SetText(Clock(elapsed))
    end
    frame.controls.pause:SetGlyph(paused and "play" or "pause")
    if sd.chunked == nil then
        sd.chunked = (addon.ClipChunkStarts and addon.ClipChunkStarts(sd.soundPath)) ~= nil
    end
    if sd.chunked then
        frame.controls.pause.tooltip = paused and "Resume: picks up at the start of the part it was paused in."
            or "Pause the narration. Resume picks up at the start of the part it was paused in."
    else
        frame.controls.pause.tooltip = paused and "Resume: the game cannot pick a clip up part-way, so the line starts again."
            or "Pause the narration. The game cannot pick a clip up part-way, so Resume starts the line again."
    end
    -- Queue position ("1/2") and Next, only while something is queued.
    local total = addon.queueTotal or 0
    if total > 1 and not sd.preview then
        frame.controls.time:SetText((addon.queuePos or 1) .. "/" .. total .. "   " .. frame.controls.time:GetText())
    end
    local showNext = not sd.preview and addon.speechQueue and #addon.speechQueue > 0
    frame.controls.next:SetShown(showNext)
    local prev = frame.controls.previous
    prev:SetShown(not sd.preview and addon.speechHistory and #addon.speechHistory > 0)
    local anchor = showNext and frame.controls.next or frame.controls.pause
    if prev.anchor ~= anchor then
        prev.anchor = anchor
        prev:ClearAllPoints()
        prev:SetPoint("RIGHT", anchor, "LEFT", -ICON_GAP, 0)
    end
end

local function ShouldShow(sd)
    if not sd then
        return false
    end
    if sd.preview then
        return true
    end
    if not DB().showSpeechFrame or sd.frameDismissed then
        return false
    end
    -- The subtitles take over the job of showing the text.
    if addon.SubtitlesEnabled and addon.SubtitlesEnabled() then
        return false
    end
    -- No longer hidden behind a Blizzard talking head (owner, 2026-11-23: it hid the bar while the quest line kept
    -- playing, "shouldn't it stay on?"): the line being read stays on screen with its text.
    if SourceWindowOpen(sd) then
        return false
    end
    if CombatMode() == "hide" and InFight() then
        return false
    end
    if SteppedAside() then
        return false
    end
    if paused then
        return true
    end
    if lingerUntil then
        return frame:IsShown() and GetTime() < lingerUntil
    end
    return sd.isPlaying
end

local function Clear()
    current = nil
    paused = false
    lingerUntil = nil
    if frame then
        frame:Hide()
    end
    if driver then
        driver:Hide()
    end
end

local function Tick()
    if not current or (lingerUntil and GetTime() >= lingerUntil) then
        Clear()
        return
    end
    if ShouldShow(current) then
        Refresh()
        -- "Fade in combat": 0.6 (was 0.3, owner 2026-11-23: "I don't think it should fade out as much").
        local faded = CombatMode() == "fade" and InFight()
        if faded ~= frame.combatFaded then
            frame.combatFaded = faded
            if frame.scroll then UpdateFades(frame.scroll) end
        end
        local alpha = faded and COMBAT_FADE_ALPHA or 1
        frame:SetAlpha(alpha)
        -- A 3D model draws at its own alpha whatever its parent's (owner, 2026-11-23: "the 3D spoken head didn't
        -- fade at all"), so it is set on the model itself.
        local m = frame.model
        if m and m:IsShown() and m.lastAlpha ~= alpha then
            m.lastAlpha = alpha
            pcall(m.SetModelAlpha, m, alpha)
            pcall(m.SetAlpha, m, alpha)
        end
        frame:Show()
    else
        frame:Hide()
    end
end

local function Watch(sd)
    Build()
    current = sd
    if not driver then
        driver = CreateFrame("Frame")
        local acc = 0
        driver:SetScript("OnUpdate", function(_, elapsed)
            acc = acc + elapsed
            if acc >= UPDATE_INTERVAL then
                acc = 0
                Tick()
            end
        end)
    end
    driver:Show()
    Tick()
end

-- --------------------------------------------------------------------------
-- Controls
-- --------------------------------------------------------------------------

function Pause()
    local sd = current
    if not sd or paused then
        return
    end
    if not sd.preview and addon.PauseSound and addon.PauseSound() then
        -- The "pause" notice sets paused and the place (shared with Read Quest and the quest log's buttons).
        return
    end
    pausedElapsed = Elapsed(sd)
    paused = true
    if not sd.preview then
        pausing = true
        addon.StopCurrentSound(true)
        pausing = false
    end
    Tick()
end

function Resume()
    local sd = current
    if not sd or not paused then
        return
    end
    paused = false
    if sd.preview then
        sd.startedAt = GetTime() - pausedElapsed
    elseif addon.PausedSound and addon.PausedSound() == sd then
        addon.ResumeSound()
    else
        -- A chunked clip picks up at the chunk it was paused in; a single-file clip starts over (head of the file).
        addon.ReplaySound(sd, pausedElapsed)
    end
    Tick()
end

function Replay()
    local sd = current
    if not sd then
        return
    end
    paused = false
    lingerUntil = nil
    if sd.preview then
        sd.startedAt = GetTime()
    else
        addon.ReplaySound(sd)
    end
    Tick()
end

function StopNarration()
    local sd = current
    if sd and not sd.preview then
        if sd.textType == "item" and addon.StopBook then
            addon.StopBook()
        elseif addon.activeSound == sd then
            addon.StopCurrentSound()
        end
        -- Stop means stop: the queue goes too.
        if addon.ClearSpeechQueue then addon.ClearSpeechQueue() end
    end
    Clear()
end

-- Close the frame but let the line finish. A paused line has nothing left
-- to finish, so closing it is the same as Stop.
function Dismiss()
    if current and (paused or current.preview) then
        StopNarration()
        return
    end
    if current then
        current.frameDismissed = true
    end
    if frame then
        frame:Hide()
    end
end

-- Global on purpose: Bindings.xml calls it by name.
function SpeakStone_TogglePause()
    if paused then
        Resume()
        return
    end
    local sd = addon.activeSound
    if sd and (sd.isPlaying or sd.nextSoundTimer) then
        if current ~= sd then
            Watch(sd)
        end
        Pause()
    end
end

-- --------------------------------------------------------------------------
-- Controller hooks (Gamepad.lua)
-- --------------------------------------------------------------------------

function addon.SpeechFrameGet()
    return frame, current
end

function addon.SpeechFrameControl(action)
    if not current then
        if action == "pause" then SpeakStone_TogglePause() end
        return
    end
    if action == "pause" then
        if paused then Resume() else Pause() end
    elseif action == "stop" then
        StopNarration()
    elseif action == "replay" then
        Replay()
    elseif action == "close" then
        Dismiss()
    elseif action == "next" then
        if current.preview or not (addon.speechQueue and #addon.speechQueue > 0) then return end
        paused = false
        lingerUntil = nil
        if addon.PlayNextQueued then addon.PlayNextQueued() end
    elseif action == "previous" then
        if current.preview or not (addon.speechHistory and #addon.speechHistory > 0) then return end
        paused = false
        lingerUntil = nil
        if addon.PlayPreviousQueued then addon.PlayPreviousQueued() end
    end
end

-- Move by (dx, dy) UIParent units; the controller's D-pad. Ignores the lock: a deliberate move.
function addon.SpeechFrameNudge(dx, dy)
    if not frame then return end
    local scale = frame:GetScale()
    local left, top = frame:GetLeft(), frame:GetTop()
    if not left then return end
    frame:ClearAllPoints()
    frame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", left + dx / scale, top + dy / scale)
    SavePosition()
end

-- One size step bigger (+1) or smaller (-1); the controller's shoulder buttons.
function addon.SpeechFrameResize(step)
    local db = DB()
    local index = 2
    local currentKey = CurrentSizeKey()
    for i, size in ipairs(SIZES) do
        if size.key == currentKey then index = i end
    end
    index = math.max(1, math.min(#SIZES, index + step))
    db[SizeKeyName()] = SIZES[index].key
    if frame then ApplyPosition() end
end

function addon.SpeechFrameResetPosition()
    DB().speechFramePos = nil
    if frame then ApplyPosition() end
end

-- /ss frame: a sample line to place and size the frame with.
function addon.SpeechFramePreview()
    if current and current.preview then
        Clear()
        return
    end
    if addon.activeSound and addon.activeSound.isPlaying then
        print("|cff33ff99SpeakStone:|r narration is playing; try again once it has finished.")
        return
    end
    paused = false
    lingerUntil = nil
    Build()
    local sd = {
        preview = true,
        text = PREVIEW_TEXT,
        npcName = "SpeakStone",
        title = "Preview",
        duration = 24,
        startedAt = GetTime(),
    }
    SetPortrait(sd)
    Watch(sd)
end

-- For the tutorial's speech bar page: show the sample (unless it is up
-- already), take it down again, and where the bar's edges are in UIParent
-- units (bottom, top) so the tutorial can keep out of its way.
function addon.SpeechFrameShowPreview()
    if not (current and current.preview) then
        addon.SpeechFramePreview()
    end
    return current ~= nil and current.preview == true
end

function addon.SpeechFrameHidePreview()
    if current and current.preview then
        Clear()
    end
end

function addon.SpeechFramePreviewShown()
    return current ~= nil and current.preview == true
end

function addon.SpeechFrameBounds()
    if not (frame and frame:IsShown() and frame:GetTop()) then
        return nil
    end
    local ratio = frame:GetEffectiveScale() / UIParent:GetEffectiveScale()
    return frame:GetBottom() * ratio, frame:GetTop() * ratio
end

-- --------------------------------------------------------------------------
-- Menu
-- --------------------------------------------------------------------------

function OpenMenu(owner)
    Build()
    local db = DB()
    if not (MenuUtil and MenuUtil.CreateContextMenu) then
        -- No menu API on this client: step through the sizes instead.
        local index = 1
        local currentKey = CurrentSizeKey()
        for i, size in ipairs(SIZES) do
            if size.key == currentKey then index = i end
        end
        db[SizeKeyName()] = SIZES[index % #SIZES + 1].key
        ApplyPosition()
        return
    end
    MenuUtil.CreateContextMenu(owner, function(_, root)
        root:CreateTitle("SpeakStone speech bar")
        -- While TV size is in force (controller, or the TV / Sofa layout) these two menus set the TV choices.
        local tvTag = TVNow() and " (controller / TV)" or ""
        local sizeMenu = root:CreateButton("Size" .. tvTag)
        for _, size in ipairs(SIZES) do
            sizeMenu:CreateRadio(size.label,
                function() return CurrentSizeKey() == size.key end,
                function() db[SizeKeyName()] = size.key; ApplyPosition() end)
        end
        local themes = root:CreateButton("Theme")
        for _, key in ipairs(addon.ThemeOrder) do
            themes:CreateRadio(addon.Themes[key].label, function() return addon.Theme().key == key end,
                function() addon.SetTheme(key) end)
        end
        local textMenu = root:CreateButton("Text size" .. tvTag)
        for _, size in ipairs(TEXT_SIZES) do
            textMenu:CreateRadio(size.label,
                function() return CurrentTextKey() == size.key end,
                function() db[TextKeyName()] = size.key; addon.SpeechSettingChanged("speechTextSize") end)
        end
        local linesMenu = root:CreateButton("Lines at a time")
        for _, n in ipairs({ 3, 4 }) do
            linesMenu:CreateRadio(n .. " lines", function() return Lines() == n end,
                function() db.speechLines = n; addon.SpeechSettingChanged("speechLines") end)
        end
        local combatMenu = root:CreateButton("In combat")
        for _, opt in ipairs({ { "show", "Keep showing" }, { "fade", "Fade it back" }, { "hide", "Hide it (the voice carries on)" } }) do
            combatMenu:CreateRadio(opt[2], function() return CombatMode() == opt[1] end,
                function() db.speechCombat = opt[1] end)
        end
        root:CreateCheckbox("Hide on flight paths",
            function() return db.speechHideOnTaxi == true end,
            function() db.speechHideOnTaxi = not (db.speechHideOnTaxi == true) end)
        root:CreateCheckbox("TV size while using a controller",
            function() return db.speechTVOnPad end,
            function()
                db.speechTVOnPad = not db.speechTVOnPad
                addon.SpeechSettingChanged("speechTextSize")
                addon.SpeechSettingChanged("speechSize")
            end)
        root:CreateCheckbox("Auto-scroll the text",
            function() return db.speechAutoScroll ~= false end,
            function() db.speechAutoScroll = db.speechAutoScroll == false end)
        root:CreateCheckbox("Show all the text (grow the frame)",
            function() return db.speechFitText end,
            function()
                db.speechFitText = not db.speechFitText
                addon.SpeechSettingChanged("speechFitText")
            end)
        root:CreateCheckbox("Compact: four scrolling lines",
            function() return db.speechCompact == true end,
            function()
                db.speechCompact = not db.speechCompact
                addon.SpeechSettingChanged("speechCompact")
            end)
        root:CreateCheckbox("Queue quests (don't interrupt)",
            function() return db.queueQuestSpeech end,
            function()
                db.queueQuestSpeech = not db.queueQuestSpeech
                addon.SpeechSettingChanged("queueQuestSpeech")
            end)
        root:CreateCheckbox("Lock position",
            function() return db.speechFrameLocked end,
            function() db.speechFrameLocked = not db.speechFrameLocked end)
        root:CreateButton("Reset position (top of the screen)", function()
            db.speechFramePos = nil
            ApplyPosition()
        end)
        if addon.SetControllerLayout then
            local pad = root:CreateButton("Controller")
            for _, opt in ipairs({ { "XBOX", "Xbox" }, { "PS", "PlayStation" }, { "KBM", "None (keyboard and mouse)" } }) do
                pad:CreateRadio(opt[2], function() return addon.ControllerLayout() == opt[1] end,
                    function() addon.SetControllerLayout(opt[1]) end)
            end
            pad:CreateDivider()
            pad:CreateTitle("Button to take the bar")
            for _, b in ipairs({ "PADBACK", "PADLSTICK", "PADRSTICK" }) do
                pad:CreateRadio(addon.ControllerLabel(b), function() return addon.ControllerFocusButton() == b end,
                    function() addon.SetControllerFocusButton(b) end)
            end
        end
        root:CreateDivider()
        if current and not current.preview and addon.OpenReportMenu then
            local reportSub = root:CreateButton("Report this voice line")
            for _, r in ipairs(addon.REPORT_REASONS or {}) do
                reportSub:CreateButton(r.label, function()
                    if addon.HarvestRecordBug and addon.HarvestRecordBug(current, r.key) then
                        print("|cffffd100SpeakStone:|r Reported |cff00ccff" .. tostring(current.soundFile) .. "|r (" .. r.label .. ") -- added to your capture export (/ssharvest export).")
                        if addon.RefreshSettingsStatus then addon.RefreshSettingsStatus() end
                    else
                        print("|cffffd100SpeakStone:|r Already reported |cff00ccff" .. tostring(current.soundFile) .. "|r (" .. r.label .. ").")
                    end
                end)
            end
        end
        root:CreateCheckbox("Auto-accept quests",
            function() return db.autoAcceptQuests end,
            function() db.autoAcceptQuests = not db.autoAcceptQuests end)
        root:CreateButton("SpeakStone settings...", function()
            if addon.ShowSettings then addon:ShowSettings() end
        end)
        root:CreateButton("Turn the speech bar off", function()
            db.showSpeechFrame = false
            print("|cff33ff99SpeakStone:|r speech bar off. Turn it back on in /ss.")
            Clear()
        end)
    end)
end

-- --------------------------------------------------------------------------
-- Notices from the playback code
-- --------------------------------------------------------------------------

-- A speech-frame option changed (the gear menu, /ss, or the game's
-- Options page): apply it to the frame now, not on the next clip.
function addon.SpeechSettingChanged(key)
    if addon.SubtitleSettingChanged then
        addon.SubtitleSettingChanged(key)
    end
    if (key == "readingFont" or key == "speechTextSize" or key == "speechLines" or key == "speechCompact"
        or key == "speechTVAlways" or key == "speechTVOnPad") and addon.SpeechFrameApplyFont then
        addon.SpeechFrameApplyFont()
        if frame then ApplyPosition() end
    end
    if addon.FontPreviewRefresh then
        addon.FontPreviewRefresh()
    end
    if key == "speechFitText" and frame then
        frame.filledFor = nil
    elseif key == "showReportButton" then
        if addon.UpdateQuestButtonVisibility then addon.UpdateQuestButtonVisibility() end
        if addon.UpdateMissingVoiceIcons then addon.UpdateMissingVoiceIcons() end
        if frame and frame:IsShown() then Refresh() end
    elseif (key == "speechSize" or key == "speechFramePos") and frame then
        ApplyPosition()
    elseif key == "queueQuestSpeech" and not DB().queueQuestSpeech and addon.ClearSpeechQueue then
        addon.ClearSpeechQueue()
    end
end

local function Notify(event, sd)
    for _, name in ipairs({ "QuestTextSyncNotify", "SubtitleNotify" }) do
        if addon[name] then
            -- Dialogue sync has no paused state: a pause is a stop to it, as it always was. Subtitles stay up, frozen.
            local sent = (event == "pause" and name == "QuestTextSyncNotify") and "stop" or event
            local ok, err = pcall(addon[name], sent, sd)
            if not ok then
                geterrorhandler()(err)
            end
        end
    end
    if event == "start" then
        if current and current.preview then
            Clear()
        end
        paused = false
        lingerUntil = nil
        Build()
        -- Only on a fresh clip: a replay after walking away has no NPC to
        -- take the portrait from, and keeps the one it had.
        if frame.portraitFor ~= sd then
            SetPortrait(sd)
            frame.portraitFor = sd
        end
        Watch(sd)
    elseif sd ~= current then
        return
    elseif event == "finish" then
        lingerUntil = GetTime() + LINGER_SECONDS
        Tick()
    elseif event == "pause" then
        -- Paused by any button (addon.PauseSound): the bar shows it paused at the same place.
        pausedElapsed = sd.pausedAt or Elapsed(sd)
        paused = true
        Tick()
    elseif event == "stop" then
        if pausing then
            return
        end
        Clear()
    end
end
function addon.SpeechFrameNotify(event, sd)
    if addon.Timed then
        addon.Timed("speech bar " .. tostring(event), Notify, event, sd)
    else
        Notify(event, sd)
    end
end
