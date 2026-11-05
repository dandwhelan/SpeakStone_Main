local addonName, addon = ...

-- Zone lore: one short piece per zone, shown by ZoneLore.lua (the zone-entry banner and the Lore tab in the settings).
--
--   map          the zone's uiMapID. A smaller map inside the zone (a district, a cave) counts as its zone: ZoneLore.lua
--                walks up to the parent map until it finds an entry here.
--   title, text  what the banner and the Lore tab show.
--   placeholder  true = the text is a stand-in written for this table, not final wording. Take the flag off when the
--                real piece goes in.
--   clip         optional clip name; default "zonelore_<map>". The clip is found like any other (a voice pack's
--                SoundLengths lists "zonelore_<map>.ogg" or ".wav"), so audio arrives by adding clips to a pack.
--                No clip installed = the banner shows the text only and the Lore tab has no Play.
--
-- uiMapIDs read from the retail client's UiMap table, build 12.1.5.70575 (wago.tools). Add a zone by adding a line;
-- if the map ID is not certain leave it out (a TODO below) rather than guess.
--
-- TODO (not Midnight zones, owner may want them later): Exile's Reach, Arathi Highlands (Hammerfall).
-- TODO: Isle of Quel'Danas (maps 2424 / 2565) is a Midnight map too; map IDs not confirmed against client data this session, so no piece yet.
addon.ZoneLoreData = {
    { map = 2395, title = "Eversong Woods",
      text = "Eversong Woods is the old forest heart of Quel'Thalas, home of the blood elves. Its golden trees and ancient wards have outlasted war, plague and the fall of the Sunwell. The scars of the Scourge's march still mark the land, and the Ghostlands to the south are now counted as part of it. Yet the forest is healing, and the quel'dorei who walk its paths mean to see it thrive again." },
    { map = 2393, title = "Silvermoon City",
      text = "Silvermoon City is the capital of the blood elves, raised around the restored Sunwell, the fountain of magic their people depend upon. Crimson and gold spires rise above its gardens and plazas, and the Convocation of Silvermoon still watches over its people. The city was battered by invasion, yet it stands again, a proud and wounded kingdom that refuses to be forgotten." },
    { map = 2437, title = "Zul'Aman",
      text = "Zul'Aman is the ancient stronghold of the Amani trolls, a people who once ruled most of the northern forests. Their great temple city rises from the jungle at the edge of Quel'Thalas, and old grudges with the elves run as deep as its roots. The Amani empire is long broken, but its drums, its ruins and its fierce spirit remain." },
    { map = 2413, title = "Harandar",
      text = "Harandar lies beneath the earth, where the roots of a great tree reach down through the dark. Strange glowing plants light the caverns like a living forest under the stone. The haranir make their home here, a secretive people bound to the wild magic around them. Few outsiders have walked these paths, and the land seems to watch every one who does." },
    { map = 2405, title = "Voidstorm",
      text = "Voidstorm is a wounded land where the Void has broken through and the sky churns with dark energy. Xal'atath gathers her power here, and the ground itself bends toward her purpose. Nothing grows easily in this place, and nothing is quite what it seems. Those who cross it carry little more than courage and a stubborn hope of turning the tide." },
}
