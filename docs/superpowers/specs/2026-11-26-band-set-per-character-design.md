# Design: the band set a container uses is the character's own

- **Date:** 2026-11-26.
- **Branch:** `feat/2026-11-26-band-set-per-character`.
- **Plan:** `docs/superpowers/plans/2026-11-26-band-set-per-character.md`.

## The report

The owner, verbatim: "I am using the Default Ace3 profile. I was on my paladin, and set the Paladin band
set. Then i switched to my hunter, same default Ace3 profile. It's still using [Paladin (default)]. Band set
selection for a single Ace3 profiel should be tied to the character you are on."

## Why it happens

A container's band sets are profile fields, `profile.containers[id].bandSet` and `.bandSetFriendly`
(`defaults/Profile.lua`). Every character on a profile reads the same two fields, so the paladin's pick
is the hunter's too. "(default)" names the first set in `bandSetOrder`, which the first-run seed filled
with the class default of the character that made the profile (`modules/BandSets.lua`, `Seed`): the
Paladin set, on every character.

## The design

### 1. Where a selection lives

A selection is stored per character, in AceDB's character scope:

```
db.char.bandSetChoice[<profile name>][<container id>] = { hostile = <set id>?, friendly = <set id> | false? }
```

- `hostile` is the container's Band set for this character. When it is nil, the character has not
  chosen and rule 2 below applies.
- `friendly` is the Friendly band set. `false` means the character chose *Same as Band set*. A set id
  is a chosen override. nil means the character has not chosen, so the profile's `bandSetFriendly`
  applies. When that is nil too, the friendly unit gets the hostile set.
- The profile's two container fields stay. They are the fallback, and they are what a new container,
  a container preset and a copy write.

One new module, `modules/BandSetChoice.lua` (`NS.BandSetChoice`), is the store's one runtime writer
(architecture-§5).

### 2. Which set a container uses (the resolution)

For the hostile set, the first of these that names a stored set wins:

1. the character's own `hostile` choice;
2. this character's class default: the first set in `bandSetOrder` whose `origin` is
   `DefaultFor(class, spec)`, else the first whose `origin` is `DefaultFor(class)`;
3. the profile's `container.bandSet`;
4. the default set, `bandSetOrder[1]`.

For the friendly set, the first of these that holds wins:

1. the character's `friendly` choice: `false` means the hostile set, and a stored id means that set;
2. the profile's `bandSetFriendly` when it names a set;
3. the hostile set.

`NS.BandSets.ForUnit(container, unit, id)` reads this resolution. The renderer and the sounds pass the
instance's container id. A caller that passes no id, and a db with no character store (the no-AceDB
fallback), keep the old reading of the profile fields alone.

### 3. Writing

- The Containers page's *Band set* and *Friendly band set* rows, and `/rm set container.bandSet` and
  `/rm set container.bandSetFriendly`, read and write the current character's choice
  (`NS.BandSetChoice.Set`). Picking *Default band set* (0) clears the hostile choice. Picking *Same as
  Band set* (0) stores `false`.
- Deleting a band set clears every choice that names it, on every character the SavedVariables hold
  (`db.sv.char`), for the active profile. When the delete names a set to move to (`reassignTo`), the
  choice moves to that set instead.
- Copying a container's band-set sections (`NS.CM.CopySettings`) and duplicating a container
  (`NS.CM.Duplicate`) copy every character's choice for the source container onto the new one.
- A profile copy copies every character's choices from the source profile's name to the active one. A
  profile reset forgets them. A profile delete forgets that profile's choices.
- The load pass (`NS:RunMigrations`, after `PrepareProfile`) prunes the current character's choices for
  the active profile. It drops a choice that names a container or a set that no longer exists.

## The calls (the lead decided these, under the owner's run guidelines)

- **C1. The store is keyed by profile name, then container id.** `db.char` is one table for each
  character, shared by every profile, and container ids repeat across profiles. Without the profile
  name, container 1 of "Default" and container 1 of "Raid" would share a choice.
- **C2. `origin` is the preset key.** Sets have recorded their preset since RangeMaster#21. The seed,
  Create and Duplicate write it, and schema v4 back-filled it by name, so no new key or back-fill is
  needed. A renamed or edited class set keeps its `origin`, so it still counts as the class default.
  When two sets share an origin (a duplicate), the first in the order wins.
- **C3. The first resolution is not written back.** Rule 2 runs each time it is needed, and its result
  is cached until the band sets, the spec or the profile change. A character that never picks keeps
  following its class default, even across a respec (Devourer) and a deleted set.
- **C4. `db.sv.char` is reachable, and it is used.** Real AceDB-3.0 keeps every character's store in
  `sv.char[<charKey>]`. A delete, a profile copy, reset or delete, and a container copy therefore reach
  every character directly. The load pass still prunes the current character, because a hand-edited
  file or a missed event can leave stale entries.
- **C5. "(default)" names this character's default.** On the Band sets page, "(default)" now marks
  the set a container with no choice resolves to for this character: rule 2's class set, else the first
  in the order. The *Band set* row's 0 entry reads "Default band set (<that set's name>)". The
  container's own profile field (rule 3) is not shown, because rule 2 wins over it whenever a class
  set exists.
- **C6. The friendly choice has three states.** nil, false and an id. With only two states, a character
  that picked a hostile set would lose a preset's Healer override on friends.
- **C7. Schema v5 keeps the migrating character's choice.** The first character to load after the update
  gets, for every container of every stored profile, its `bandSet` as its own hostile choice. The
  exception is a set whose `origin` is another class's preset: that set is not pinned, so the order
  of logins does not matter. The paladin keeps Paladin, and a hunter logging in first still gets
  Hunter. The friendly field is not migrated; nil already falls back to it. Characters that load later
  get rule 2.
- **C8. Without a character store, the old reading stays.** The no-AceDB fallback db and the test
  kit's AceDB fake have no `db.char`. There the rows and `ForUnit` read and write the profile fields as
  before, so the existing suite measures unchanged behavior. The new suite builds a db with `char` and
  `sv.char`.
- **C9. A chosen set wins over the class default; a class default wins over the profile field.** This is
  the owner's rule: the selection is tied to the character. One cost: a container preset's
  `bandSet` choice (for example *Expert*'s default set) yields to each character's class set. *Ka0s*
  already picks the class set.

## Out of scope

- No per-character store for any other setting.
- No version bump and no release.
