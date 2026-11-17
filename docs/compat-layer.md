# Compat layer — Ka0s Range Master

`core/Compat.lua` is the whole compat family (compat) and publishes **14** shims on `NS.Compat`,
counted with the command documentation-§3 fixes:

```sh
cat core/Compat*.lua | grep -cE '^\s*function\s+[A-Za-z_][A-Za-z0-9_]*\.'    # 14
```

Four of them (`IsForever`, `IsRetail`, `ClientKey`, `ForClient`) only route `LibKa0s-Compat-1.0`'s
answer to "which client is this" (clients-§3), each with a library-absent stand-in that answers
Retail. The secret guards (`IsSecret`, `CanAccess`, `IsSafeKey`) and the spell-info reader
(`GetSpellInfo`) are the library's members handed over by reference, with the one-rung bodies the
library's degradation rule asks for; they are LibKa0s's and are not documented again here. The ten
below are this addon's own.

## The range reads and the ladder

Every client range read outside LibRangeCheck-3.0 lands here (design spec 5.1). Each is called inside
`pcall`, and its answer is passed through `IsSecret` before anything compares or tests it: a raise, a
secret, or a value that is neither a boolean nor 1/0 answers `nil`, "no answer", which
`modules/Range.lua` reads as unknown and never as out of range (events-frames-taint-§8).

| # | Shim | Wraps | Absent or refused | Why it exists | Called from |
|---|---|---|---|---|---|
| 1 | `IsEventValid(name)` | `C_EventUtils.IsEventValid` (pcall) | `true`: the refusal is left to `NS.SafeRegisterEvent` | `PLAYER_FOCUS_CHANGED` may not exist on WoW Forever (design spec 3); the event list's `ifValid` rows ask before registering | `core/RangeMaster.lua` (`RegisterLifecycleEvents`) |
| 2 | `IsSpellKnown(id)` | `C_SpellBook.IsSpellKnown` (pcall, secret-checked) | `false` | Only a known spell is range-checked: an unlearned one can report "in range" from anywhere | `modules/Range.lua` (`InSpellRange`, cached until `SPELLS_CHANGED`), shim 8 |
| 3 | `IsSpellUsable(id)` | `C_Spell.IsSpellUsable` (pcall, both answers secret-checked) | `false` | The other half of research lesson 9: a known spell unusable in the current form or stance can report "in range" from anywhere. Short of power still counts as usable | `modules/Range.lua` (`InSpellRange` and the ladder walk's spell rungs, asked per call and never cached: a shapeshift fires no `SPELLS_CHANGED`) |
| 4 | `SpellInRange(id, unit)` | `C_Spell.IsSpellInRange` | `nil` | The spell chips and the ladder's spell rungs | `modules/Range.lua` |
| 5 | `ItemInRange(id, unit)` | `C_Item.IsItemInRange` | `nil` | Forever's item rungs. The client refuses it on a unit the player cannot attack in combat; the caller skips it there | `modules/Range.lua` (the ladder walk) |
| 6 | `InteractInRange(index, unit)` | `CheckInteractDistance(unit, index)` | `nil` | Forever's interact rungs. Protected on a friendly unit in combat; skipped there | `modules/Range.lua` (the ladder walk) |
| 7 | `CanAttack(unit)` | `UnitCanAttack("player", unit)` | `nil`, which the caller reads as "cannot", the side that never asks a blocked check | The combat restriction's one question | `modules/Range.lua` (the ladder walk) |
| 8 | `RangeLadder()` | `ClientKey`, `UnitRace`, `UnitClass`, shim 2, `GetSpellInfo` | Retail: spell rungs only; no class or race read: no spell rungs, no race offset | The per-client rung list, sorted by yd (below) | `modules/Range.lua`, built on first use and again on `SPELLS_CHANGED` |
| 9 | `IsFriend(unit)` | `UnitIsFriend("player", unit)` (pcall, secret-checked) | `nil`, which the caller reads as "not friendly": the container stays on its own band set | A band set's friendly override applies only to a unit the client says is friendly | `modules/BandSets.lua` (`ForUnit`) |
| 10 | `PlayerClass()` | `UnitClass("player")`'s class token (pcall, secret-checked) | `nil`: the seed picks Melee / Ranged | The first-run band-set seed puts the class default first | `modules/BandSets.lua` (the seed routine) |

## `RangeLadder()`: what each client gets

`{ { kind = "item"|"interact"|"spell", id = number, yd = number }, ... }`, sorted by `yd` ascending.

| Rung | Retail | WoW Forever |
|---|---|---|
| Items | none: LibRangeCheck owns Retail's item tables | 20 yd: 10645, 1191, 4388; 30 yd: 835, 2091, 7734, 17202; 35 yd: 18904, 1399, 1402. Forever's item checks are reliable only at these three yards (AppelSwingsForever `Bands.lua`, each ID verified on Forever 1.60.1 and listed in LibRangeCheck-3.0's Era harm table at the same yard) |
| Interact | none | index 3 (duel) at 10 yd and index 4 (follow) at 28 yd, the vanilla distances; Tauren −2 / −3 and Scourge −1 / −1, the offsets LibRangeCheck-3.0 measured for the two large-hitbox races |
| Spells | the player's class `ladder` seeds from `defaults/SpellSeeds.lua` that the player knows, with a max range above 0 and no min range, at that max range | the same, from the `forever` seeds |

Retail's ladder is built but not walked today: `modules/Range.lua` walks it only on Forever, and only
when LibRangeCheck answered nothing for a unit that exists. In combat on a unit the player cannot
attack (shim 7), the walk asks the spell rungs only.

## Rules for this file

- A feature module calls `NS.Compat.X`, never the global it wraps.
- No file outside `core/Compat.lua` reads a `WOW_PROJECT_*` global or the build's interface number
  (`tests/test_compat.lua`).
- Every shim answers something sensible when its API is absent, because the headless harness and a
  partial install both reach that branch.
