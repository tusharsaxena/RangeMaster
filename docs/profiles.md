# Profiles — Ka0s Range Master

AceDB-3.0 profiles are user-visible: the Profiles sub-page (`settings/Profiles.lua`) draws
AceDBOptions' table, and `/rm profile [name]` lists profiles or switches to an existing one.

## What is per profile, and what is not

- **Per profile:** everything under `db.profile` (`docs/schema.md`): the Master controls, the skin
  choice, both registries (the containers and the band sets) and the first-run sentinel `seeded`. A
  new profile starts with no container and one band set, its creator's class (or spec) preset, and is
  offered the first-run preset picker. Other sets join it as characters load on it or the player
  makes them (R4-RM-02); a profile made before that keeps every set it has.
- **Per character, within each profile:** `db.char.bandSetAssigned`, the band set each character is
  assigned on each profile (written at its first load there, changed only by **Use for this
  character** on the Band sets page or a delete of the set), and `db.char.bandSetChoice`, which holds
  the Band set and Friendly band set each character picked for each container (`modules/BandSetChoice.lua`,
  `docs/schema.md` The character store). A profile copy carries every character's assignment and picks
  to the new profile, and a reset or a delete forgets them (`OnProfileDeleted`); after a reset only the
  character that reset it is assigned again, at once.
- **Installation-wide:** `db.global` — the schema stamp, the minimap button (`global.minimap`, so a
  profile switch never moves the button) and the one-time skin notice.
- **Session only:** the debug flag, Test mode, Sim mode, the selected container and band set, and
  the preset Undo slot.

## What a profile event does

`core/Database.lua` registers AceDB's `OnProfileChanged`, `OnProfileCopied` and `OnProfileReset`;
each lands in `core/RangeMaster.lua`'s `adoptProfile`:

- one debug line in the event's own words (`[Profile] changed -> <name>`, `[Set] copied profile ...`,
  `[Set] reset profile '<name>' to defaults (N rows)`);
- the skin picker and the preset picker go down unmarked, before the new profile's skin is applied.
  A switch takes the preset picker down earlier, at AceDB's `OnProfileShutdown`, so a preview it had
  up is restored into the old profile; a reset or a copy drops that preview instead (the profile was
  replaced whole);
- the new profile is migrated and backfilled, and its registries repaired
  (`Database.PrepareProfile`);
- the preset Undo slot is dropped (`NS.Presets.ForgetUndo`): it held the old profile's containers;
- the band sets' Undo slot is dropped (`NS.ForgetBandSetUndo`) and an open band-set dialog closes
  (`NS.HideBandSetDialog`, `settings/BandSetDialogs.lua`);
- its skin is applied and the latch is re-read from its `enabled`, so switching to a profile where the
  addon is off stands it down, and back brings it up (slash-commands-§7);
- one container apply is asked for (`NS.CM.RequestApply`), so the displays become the new profile's
  on the next frame, held through combat;
- both selections are cleared, so the pages and `container.` / `bandSet.` paths read the new
  profile's first container and default band set;
- the first-run preset picker is offered to a profile that has not seen it, the skin picker behind
  it, and an open panel refreshes.

**Reset all settings** (the button, `/rm resetall`) is a profile reset: it keeps the minimap row and
counts the rows it changed for the debug line (options-ui-§12, debug-logging-§10).
