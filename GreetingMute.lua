local addonName, addon = ...

-- "Silence Blizzard's greeting clips": the game's own NPC greeting and
-- farewell recordings (GreetingSounds.lua) are muted file by file. The
-- Dialog-channel mute only starts with a SpeakStone clip, so a greeting that
-- plays the moment the window opens was never covered by it.

local muted = false

function addon.ApplyGreetingMute()
    local want = SpeakStone_MainDB and SpeakStone_MainDB.muteGreetingClips and true or false
    if want == muted or not (MuteSoundFile and UnmuteSoundFile and addon.GreetingSoundFiles) then
        return
    end
    local fn = want and MuteSoundFile or UnmuteSoundFile
    for _, fileID in ipairs(addon.GreetingSoundFiles) do
        pcall(fn, fileID)
    end
    muted = want
end

local loader = CreateFrame("Frame")
loader:RegisterEvent("PLAYER_LOGIN")
loader:SetScript("OnEvent", function(self)
    self:UnregisterEvent("PLAYER_LOGIN")
    addon.ApplyGreetingMute()
end)
