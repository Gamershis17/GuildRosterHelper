Guild Roster Helper v2.0.2 -- Front Desk version
A WoW Classic addon for guild leaders and officers.
Built for Burning Crusade Classic Anniversary Edition, and works on
Classic Era, Cataclysm Classic, and Mists of Pandaria Classic too.
v2.0.1 also loads on Midnight (retail): the roster and requests tabs
work there, but profession sharing is Classic-only for now, because
Midnight replaced the tradeskill API the scanner uses.
v2.0.2 adds the dragon crest logo as the in-game addon list icon.
v2.0.3 adds retail interface numbers for 12.1.x (12.1.0/12.1.5/12.1.7),
so Midnight clients on 12.1.5 load it without an out-of-date flag.

WHAT IT DOES
- /grh opens one window with three tabs: Roster, Professions, Requests.
- ROSTER: search by name, class, zone, or rank; Online-only toggle;
  sort by Name, Level, or Class; guild name, online/total counts, and
  a class breakdown of who's online. Click a name to whisper them,
  Shift-click to invite, hover for rank, zone, and notes.
- PROFESSIONS: pick a profession along the bottom and see every
  recipe your guild knows, with how many crafters know each one.
  Pick a recipe to see its crafters, their skill, and a green dot
  when they're online. Hit Request to whisper that crafter (and, if
  they run the addon, drop it in their Requests tab).
  "View: Players" flips the list to guildmates who share data, with
  their professions and skills.
- REQUESTS: crafting requests sent to you land here. Click one to
  whisper the requester back, X to dismiss it, Clear all to empty it.

HOW PROFESSION SHARING WORKS
- The game never tells an addon what recipes other players know.
  Each guildmate running this addon shares their own recipes when
  they open a profession window, and when the addon asks the guild
  (once after login, and when you open the Professions tab).
- So: install it yourself for the roster right away, and ask your
  crafters to install it too. The more guildmates running it, the
  fuller the profession lists get.

HONEST LIMITS
- Recipes only appear for guildmates running the addon. Members
  without it don't show up in profession lists at all.
- Reagent lists show only for recipes YOU know yourself. For a
  guildmate's recipe you see who can craft it and their skill --
  ask them for the materials.
- The header shows how many recipes the guild knows. There is no
  "of 222" total, because the game doesn't publish a full recipe
  list to addons -- any total would be a guess.
- Poisons isn't listed: it's a rogue class skill, not a trade
  profession. Everything else from Alchemy to Tailoring is there.

INSTALL
1. Copy the GuildRosterHelper folder (the one containing the .toc file)
   into your WoW addons folder:
   - Burning Crusade Anniversary / Cataclysm / Mists Classic:
     World of Warcraft/_classic_/Interface/AddOns
   - Classic Era: World of Warcraft/_classic_era_/Interface/AddOns
2. Restart WoW (or fully log out and back in).
3. At the character screen, click AddOns and make sure
   Guild Roster Helper is ticked.
4. In game, type /grh. Open a profession window once to share
   your own recipes with the guild.

UPLOAD TO CURSEFORGE
1. Zip the GuildRosterHelper folder so the folder itself is at the
   top level of the zip (not nested inside another folder).
2. On CurseForge, create a project: game World of Warcraft,
   category Addons, and upload the zip.
3. Pick the game versions it supports (Burning Crusade Anniversary,
   Era, Cata, MoP), set the release type, write a description,
   and submit. New projects go through a short approval review
   before going live.

CUSTOMIZE
- Change the ## Author: and ## Version: lines in
  GuildRosterHelper.toc before each release.
- The .toc declares Interface numbers for Burning Crusade Anniversary
  (20506), Era (11509), Cata (40402), and Mists (50504). If a new patch
  flags the addon as out of date, bump the matching number.

v2.0.4: slash command is registered before the window is built, and any window error now prints in chat instead of failing silently. The addon also prints a loaded message at login.
