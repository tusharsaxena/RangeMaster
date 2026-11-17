# Profiles — Ka0s Range Master

AceDB-3.0 profiles are user-visible: the Profiles sub-page (`settings/Profiles.lua`) draws
AceDBOptions' table, and `/rm profile [name]` lists profiles or switches to an existing one.

## What is per profile, and what is not

- **Per profile:** every row under `db.profile` (`docs/schema.md`): the Master controls and the skin
  choice today, and the containers and band sets once they exist.
- **Installation-wide:** `db.global` — the schema stamp, the minimap button (`global.minimap`, so a
  profile switch never moves the button) and the one-time skin notice.
- **Session only:** the debug flag, Test mode and Sim mode.

## What a profile event does

`core/Database.lua` registers AceDB's `OnProfileChanged`, `OnProfileCopied` and `OnProfileReset`;
each lands in `core/RangeMaster.lua`'s `adoptProfile`:

- one debug line in the event's own words (`[Profile] changed -> <name>`, `[Set] copied profile ...`,
  `[Set] reset profile '<name>' to defaults (N rows)`);
- the skin picker goes down unmarked, before the new profile's skin is applied;
- the new profile is migrated and backfilled, its skin applied;
- the latch is re-read from the new profile's `enabled`, so switching to a profile where the addon is
  off stands it down, and back brings it up (slash-commands-§7);
- the skin picker is offered again to a profile that has not closed it, and an open panel refreshes.

**Reset all settings** (the button, `/rm resetall`) is a profile reset: it keeps the minimap row and
counts the rows it changed for the debug line (options-ui-§12, debug-logging-§10).
