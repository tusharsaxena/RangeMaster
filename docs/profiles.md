# Profiles — Ka0s Range Master

AceDB-3.0 profiles are user-visible: the Profiles sub-page (`settings/Profiles.lua`) draws
AceDBOptions' table, and `/rm profile [name]` lists profiles or switches to an existing one.

## What is per profile, and what is not

- **Per profile:** everything under `db.profile` (`docs/schema.md`): the Master controls, the skin
  choice, both registries (the containers and the band sets) and the first-run sentinel `seeded`. A
  new profile starts with no container and the four preset band sets, and is offered the first-run
  preset picker.
- **Installation-wide:** `db.global` — the schema stamp, the minimap button (`global.minimap`, so a
  profile switch never moves the button) and the one-time skin notice.
- **Session only:** the debug flag, Test mode, Sim mode, the selected container and band set, and
  the preset Undo slot.

## What a profile event does

`core/Database.lua` registers AceDB's `OnProfileChanged`, `OnProfileCopied` and `OnProfileReset`;
each lands in `core/RangeMaster.lua`'s `adoptProfile`:

- one debug line in the event's own words (`[Profile] changed -> <name>`, `[Set] copied profile ...`,
  `[Set] reset profile '<name>' to defaults (N rows)`);
- the skin picker and the first-run preset picker go down unmarked, before the new profile's skin is
  applied;
- the new profile is migrated and backfilled and its registries repaired (`Database.PrepareProfile`);
- the preset Undo slot is dropped (`NS.Presets.ForgetUndo`): it held the old profile's containers;
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
