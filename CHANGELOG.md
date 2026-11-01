# VoteAnon — Changelog

## 1.6
- Removed: a leftover debug log that stored Lua errors from all addons in VoteAnon's saved variables, without any limit.

## 1.5
- Fixed: 1 min and 2 min polls always ended after 30 seconds.
- Fixed: stopping a poll early left its timer running, which could end the next poll too soon.
- Fixed: poll and result lines could appear in the wrong order in guild chat. Each line now waits for the previous one to come back from the server.
- Changed: the "Stop poll" button only reacts to a click made with the mouse over it.

## 1.3
- Fixed: the organizer's own vote is now counted in group, raid and guild polls.

## 1.2
- Added German (deDE) and Italian (itIT). All 11 official WoW locales are now covered.

## 1.1
- Automatic language detection based on the client's locale: English, French, Spanish, Portuguese, Russian, Korean, Simplified and Traditional Chinese. Falls back to English if a translation is missing. (Japanese not included: no WoW client is officially localized in Japanese.)

## 1.0
Initial release.
- Create a 2-4 choice poll and post it to your group, raid, or guild via `/vote`.
- Only the organizer needs the addon — everyone else votes by typing 1-4 in chat, no install required.
- Poll duration: 30 sec / 1 min / 2 min.
- Solo test mode ("Me" button) to try the whole flow without a second player.
- Manual "Stop poll" button with a live countdown.
- Raid target marker icons (star, circle, diamond, triangle) on the choices.
