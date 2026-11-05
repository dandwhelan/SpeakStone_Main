local addonName, addon = ...

-- Zone lore (owner picks 2026-11-01: the zone-entry banner and the Lore tab in the settings).
--
--   * The banner is OFF by default (zoneLoreBanner). When on, crossing into a zone that has a lore piece shows a slim
--     banner once, with Listen when a clip is installed; a zone is announced once, ever (zoneLoreHeard in the saved
--     variables), whether the player listens or not.
--   * The Lore tab (SpeakStone_Main_Settings.lua) lists the zones, heard or new, and plays or stops any of them at any
--     time, banner on or off.
--   * Audio goes through the normal playback path (addon.ReplaySound), so the speech frame and subtitles show it with
--     the narrator's name. The clip is found like every other (addon.FindSound over the installed packs).
-- The pieces are in ZoneLoreData.lua. Loaded after Subtitles/Harvester so ReplaySound and the theme exist.

local BANNER_SECONDS = 10
local MAX_PARENT_HOPS = 8
local NARRATOR = "Narrator"

local byMap
local function Index()
    if byMap then return byMap end
    byMap = {}
    for _, entry in ipairs(addon.ZoneLoreData or {}) do
        byMap[entry.map] = entry
    end
    return byMap
end

local function Heard()
    if not SpeakStone_MainDB then return {} end
    SpeakStone_MainDB.zoneLoreHeard = SpeakStone_MainDB.zoneLoreHeard or {}
    return SpeakStone_MainDB.zoneLoreHeard
end

function addon.ZoneLoreEnabled()
    return SpeakStone_MainDB ~= nil and SpeakStone_MainDB.zoneLoreBanner == true
end

-- The lore entry for a map, or for the nearest parent map that has one (a district or cave inside the zone).
function addon.ZoneLoreEntryFor(mapID)
    local index = Index()
    local guard = 0
    while mapID and mapID ~= 0 and guard < MAX_PARENT_HOPS do
        if index[mapID] then return index[mapID] end
        local ok, info = pcall(C_Map.GetMapInfo, mapID)
        mapID = ok and type(info) == "table" and info.parentMapID or nil
        guard = guard + 1
    end
    return nil
end

function addon.ZoneLoreHeard(entry)
    return entry ~= nil and Heard()[entry.map] == true
end

function addon.ZoneLoreMarkHeard(entry)
    if entry then Heard()[entry.map] = true end
end

local function ClipBase(entry)
    return entry.clip or ("zonelore_" .. entry.map)
end

-- file, path, duration -- or nil when no installed pack has the clip.
function addon.ZoneLoreClip(entry)
    if not entry or not addon.FindSound then return nil end
    return addon.FindSound({ ClipBase(entry) })
end

-- Every zone for the Lore tab, in table order.
function addon.ZoneLoreList()
    local list = {}
    for _, entry in ipairs(addon.ZoneLoreData or {}) do
        list[#list + 1] = {
            entry = entry, title = entry.title, text = entry.text, placeholder = entry.placeholder,
            heard = addon.ZoneLoreHeard(entry), hasClip = addon.ZoneLoreClip(entry) ~= nil,
        }
    end
    return list
end

function addon.ZoneLoreIsPlaying(entry)
    local sd = addon.activeSound
    return entry ~= nil and sd ~= nil and sd.questID == ClipBase(entry) and sd.isPlaying == true
end

function addon.ZoneLoreStop(entry)
    local sd = addon.activeSound
    if sd and sd.textType == "lore" and (entry == nil or sd.questID == ClipBase(entry)) then
        addon.StopCurrentSound()
    end
end

-- Play (or restart) a zone's clip. Returns false when no clip is installed.
function addon.ZoneLorePlay(entry)
    local file, path, duration = addon.ZoneLoreClip(entry)
    if not path then return false end
    addon.ZoneLoreMarkHeard(entry)
    addon.ReplaySound({
        questID = ClipBase(entry), textType = "lore",
        soundFile = file, soundPath = path, duration = duration,
        npcName = NARRATOR, title = entry.title, text = entry.text,
    })
    return true
end

-- --------------------------------------------------------------------------
-- The banner. Built on first use, so a player who never turns it on pays nothing.
-- --------------------------------------------------------------------------

local banner, bannerTimer

local function PaintBanner()
    if not banner then return end
    local ui = addon.Theme().ui
    banner.back:SetColorTexture(ui.panel[1], ui.panel[2], ui.panel[3], 0.95)
    banner.border:SetColor(ui.edge[1], ui.edge[2], ui.edge[3], 1)
    banner.kicker:SetTextColor(ui.dim[1], ui.dim[2], ui.dim[3])
    banner.title:SetTextColor(ui.title[1], ui.title[2], ui.title[3])
    banner.text:SetTextColor(ui.text[1], ui.text[2], ui.text[3])
end

function addon.ZoneLoreHideBanner()
    if bannerTimer then
        bannerTimer:Cancel()
        bannerTimer = nil
    end
    if banner then banner:Hide() end
end

local function BuildBanner()
    banner = CreateFrame("Frame", "SpeakStoneZoneLoreBanner", UIParent)
    banner:SetSize(420, 118)
    banner:SetPoint("TOP", UIParent, "TOP", 0, -150)
    banner:SetFrameStrata("HIGH")
    banner:Hide()
    banner.back = banner:CreateTexture(nil, "BACKGROUND")
    banner.back:SetAllPoints()
    banner.border = addon.UIK.MakeBorder(banner)
    banner.kicker = banner:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    banner.kicker:SetPoint("TOPLEFT", 14, -10)
    banner.kicker:SetText("Now entering")
    banner.title = banner:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    banner.title:SetPoint("TOPLEFT", banner.kicker, "BOTTOMLEFT", 0, -2)
    banner.text = banner:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    banner.text:SetPoint("TOPLEFT", banner.title, "BOTTOMLEFT", 0, -6)
    banner.text:SetWidth(392)
    banner.text:SetJustifyH("LEFT")
    banner.listen = addon.UIK.Button(banner, "Listen", 90, 24, function()
        if banner.entry then addon.ZoneLorePlay(banner.entry) end
        addon.ZoneLoreHideBanner()
    end)
    banner.listen:SetPoint("BOTTOMLEFT", 14, 10)
    banner.skip = addon.UIK.Button(banner, "Skip", 70, 24, function() addon.ZoneLoreHideBanner() end)
    banner.skip:SetPoint("LEFT", banner.listen, "RIGHT", 6, 0)
    if addon.ThemeRegister then addon.ThemeRegister(PaintBanner) end
    PaintBanner()
end

function addon.ZoneLoreShowBanner(entry)
    if not banner then BuildBanner() end
    banner.entry = entry
    banner.title:SetText(entry.title)
    banner.text:SetText(entry.text)
    local hasClip = addon.ZoneLoreClip(entry) ~= nil
    banner.listen:SetShown(hasClip)
    banner.skip:ClearAllPoints()
    if hasClip then
        banner.skip:SetPoint("LEFT", banner.listen, "RIGHT", 6, 0)
        banner.skip:SetText("Skip")
    else
        banner.skip:SetPoint("BOTTOMLEFT", 14, 10)
        banner.skip:SetText("Close")
    end
    banner:Show()
    if bannerTimer then bannerTimer:Cancel() end
    bannerTimer = C_Timer.NewTimer(BANNER_SECONDS, function()
        bannerTimer = nil
        if banner then banner:Hide() end
    end)
end

-- A zone was entered. Banner off (the default), no lore for the zone, or already announced = nothing happens.
function addon.ZoneLoreOnZone(mapID)
    if not addon.ZoneLoreEnabled() then return false end
    local entry = addon.ZoneLoreEntryFor(mapID)
    if not entry or addon.ZoneLoreHeard(entry) then return false end
    addon.ZoneLoreMarkHeard(entry)
    addon.ZoneLoreShowBanner(entry)
    return true
end

local function CheckZone()
    if not addon.ZoneLoreEnabled() then return end
    local ok, mapID = pcall(C_Map.GetBestMapForUnit, "player")
    if ok and mapID then addon.ZoneLoreOnZone(mapID) end
end

local events = CreateFrame("Frame")
events:RegisterEvent("ZONE_CHANGED_NEW_AREA")
events:RegisterEvent("PLAYER_ENTERING_WORLD")   -- logging in or reloading inside a zone fires no zone change
events:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_ENTERING_WORLD" then
        -- The map is not always known on the loading screen's last frame.
        C_Timer.After(2, CheckZone)
    else
        CheckZone()
    end
end)
