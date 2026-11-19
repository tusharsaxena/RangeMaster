# Compat layer — Ka0s Range Master

`core/Compat.lua` is the whole compat family (compat) and publishes **24** shims on `NS.Compat`,
counted with the command documentation-§3 fixes:

```sh
cat core/Compat*.lua | grep -cE '^\s*function\s+[A-Za-z_][A-Za-z0-9_]*\.'    # 24
```

Four of them (`IsForever`, `IsRetail`, `ClientKey`, `ForClient`) only route `LibKa0s-Compat-1.0`'s
answer to "which client is this" (clients-§3), each with a library-absent stand-in that answers
Retail. The secret guards (`IsSecret`, `CanAccess`, `IsSafeKey`) and the spell-info reader
(`GetSpellInfo`) are the library's members handed over by reference, with the one-rung bodies the
library's degradation rule asks for; they are LibKa0s's and are not documented again here. The
twenty below are this addon's own.

## The range reads and the ladder

Every client range read outside LibRangeCheck-3.0 lands here (design spec 5.1). Each is called inside
`pcall`, and its answer is passed through `IsSecret` before anything compares or tests it: a raise, a
secret, or a value that is neither a boolean nor 1/0 answers `nil`, "no answer", which
`modules/Range.lua` reads as unknown and never as out of range (events-frames-taint-§8).

| # | Shim | Wraps | Absent or refused | Why it exists | Called from |
|---|---|---|---|---|---|
| 1 | `IsEventValid(name)` | `C_EventUtils.IsEventValid` (pcall) | `true`: the refusal is left to `NS.SafeRegisterEvent` | `PLAYER_FOCUS_CHANGED` may not exist on WoW Forever (design spec 3); the event list's `ifValid` rows ask before registering | `core/RangeMaster.lua` (`RegisterLifecycleEvents`) |
| 2 | `IsSpellKnown(id)` | `C_SpellBook.IsSpellKnown` (pcall, secret-checked) | `false` | Only a known spell is range-checked: an unlearned one can report "in range" from anywhere | `modules/Range.lua` (`InSpellRange`, cached until `SPELLS_CHANGED`; the anchor resolver), shims 8, 11 and 12 |
| 3 | `IsSpellUsable(id)` | `C_Spell.IsSpellUsable` (pcall, both answers secret-checked) | `false` | The other half of research lesson 9: a known spell unusable in the current form or stance can report "in range" from anywhere. Short of power still counts as usable | `modules/Range.lua` (`InSpellRange` and the ladder walk's spell rungs, asked per call and never cached: a shapeshift fires no `SPELLS_CHANGED`), shim 12 |
| 4 | `SpellInRange(id, unit)` | `C_Spell.IsSpellInRange` | `nil` | The spell chips and the ladder's spell rungs | `modules/Range.lua`, shim 12 |
| 5 | `ItemInRange(id, unit)` | `C_Item.IsItemInRange` | `nil` | Forever's item rungs. The client refuses it on a unit the player cannot attack in combat; the caller skips it there | `modules/Range.lua` (the ladder walk) |
| 6 | `InteractInRange(index, unit)` | `CheckInteractDistance(unit, index)` | `nil` | Forever's interact rungs. Protected on a friendly unit in combat; skipped there | `modules/Range.lua` (the ladder walk) |
| 7 | `CanAttack(unit)` | `UnitCanAttack("player", unit)` | `nil`, which the caller reads as "cannot", the side that never asks a blocked check | The combat restriction's one question | `modules/Range.lua` (the ladder walk) |
| 8 | `RangeLadder()` | `ClientKey`, `UnitRace`, `UnitClass`, shim 2, `GetSpellInfo` | Retail: spell rungs only; no class or race read: no spell rungs, no race offset | The per-client rung list, sorted by yd (below) | `modules/Range.lua`, built on first use and again on `SPELLS_CHANGED` |
| 9 | `IsFriend(unit)` | `UnitIsFriend("player", unit)` (pcall, secret-checked) | `nil`, which the caller reads as "not friendly": the container stays on its own band set | A band set's friendly override applies only to a unit the client says is friendly | `modules/BandSets.lua` (`ForUnit`) |
| 10 | `PlayerClass()` | `UnitClass("player")`'s class token (pcall, secret-checked) | `nil`: the seed picks Melee / Ranged | The first-run band-set seed puts the class default first | `modules/BandSets.lua` (the seed routine) |

## The anchor-spell reads (band rules)

A band's spell rule (dynamic-bands plan) asks its role's anchor spell "in range?". The anchors per
class per client are `defaults/SpellSeeds.lua`'s `anchors` lists. The two spell reads are built on
shims 2 to 4 and wrap no client call a second time; only `C_Spell.GetOverrideSpell` is new, called
inside `pcall` with its answer secret-checked. The form read keys a druid's melee anchor. Shims 18
and 19 joined this table in the cross-validation round (2026-11-19), after the frame reads were numbered.

| # | Shim | Wraps | Absent or refused | Why it exists | Called from |
|---|---|---|---|---|---|
| 11 | `CurrentSpellID(id)` | `GetSpellInfo(id)`'s name, `GetSpellInfo(name)`'s spellID, `C_Spell.GetOverrideSpell` (pcall, secret-checked), shim 2 | `nil` when the client has no such spell or no spell-info reader; the ID itself when the name lookup answers nothing; an override only when the player knows it | A Forever seed is rank 1, and asking rank 1 once a higher rank is learned is unverified: resolve to the learned rank by the client's own localized name, as LibRangeCheck-3.0's `findSpellIdx` does (research part 2, correction 10), then to a hero-talent override | `modules/Range.lua` (the anchor resolver, at rebuild) |
| 12 | `AnchorInRange(id, unit)` | shims 2, 3 and 4 | `nil` unless the spell is known and usable now; the client's `nil`, a raise or a secret stay `nil`, never `false` | A band's spell rule reads a nil as "cannot say", and the band falls back to its yards | `modules/Range.lua` (`RoleInRange`, through the per-tick spell memo) |
| 13 | `ShapeshiftFormID()` | `GetShapeshiftFormID` (pcall, secret-checked) | `nil`: no form, which keys no form's anchor | A druid's melee anchor is keyed by form (Cat, Bear), and a form's strike answers only in that form | `modules/Range.lua` (`Anchor`, on each read, so a shift is followed before the rebuild's debounce fires) |
| 18 | `OverrideSpell(id)` | `C_Spell.GetOverrideSpell` (pcall, secret-checked) | `nil`: no override, or the client will not say | What stands in for a spell now: CurrentSpellID's override step at rebuild, and the melee guard's live check (Aspect of the Eagle's 40 yd Raptor Strike, Ascendance's Windstrike) | `core/Compat.lua` (CurrentSpellID), `modules/Range.lua` (the melee guard) |
| 19 | `PlayerSpecID()` | LibKa0s-Compat `GetSpecialization` and `GetSpecializationInfo` (pcall, secret-checked) | `nil` on a client with no specs (WoW Forever) or a partial install | The first-run seed's spec-aware default (Devourer reads as a caster) | `modules/BandSets.lua` (Seed) |

## The frame reads the anchors make

A nameplate can be forbidden (a friendly plate in an instance on 12.x), and any method call on one
raises. Each read below asks `IsForbidden` first, under `pcall`; a raise or a secret answer counts as
forbidden, and a forbidden plate is answered as `nil`, so no caller ever touches one.
Shim 20, the cast read, joined this table with the plate cast bar part (2026-11-20); it reads a unit,
not a frame.

| # | Shim | Wraps | Absent or refused | Why it exists | Called from |
|---|---|---|---|---|---|
| 14 | `NamePlateForUnit(unit)` | `C_NamePlate.GetNamePlateForUnit` (pcall, forbidden-checked) | `nil` | A plate token's plate, and the own-plate containers' "target" / "focus" / "mouseover" plate | `modules/Anchors_Nameplate.lua` |
| 15 | `PlateToken(plate)` | the plate's `namePlateUnitToken` (pcall, forbidden- and secret-checked) | `nil` | The token a scanned plate serves | shim 16 |
| 16 | `NamePlates()` | `C_NamePlate.GetNamePlates` (pcall), shim 15 per plate | `{}` | The stand-up's rescan: a stood-down addon heard no `NAME_PLATE_UNIT_ADDED` for the plates shown | `modules/Anchors_Nameplate.lua` (`StandUp`) |
| 17 | `GetMouseFocus()` | `GetMouseFoci()[1]` (pcall) | `nil` | The frame picker's frame under the cursor; both clients carry `GetMouseFoci` | `modules/FramePicker.lua` |
| 20 | `IsCasting(unit)` | `UnitCastingInfo`, then `UnitChannelInfo` (each presence-tested, pcall; only `type()` of the answer is read, which a secret allows) | `nil` when neither read exists (WoW Forever) or both raised | A nameplate container's *Cast bar while casting* part: whether a plate's unit casts when no cast event has spoken for it yet, and after a stop-kind event (a channel can follow a cast) | `modules/Anchors_Nameplate.lua` |

The unit-frame names the `ellesmere` provider reads (`modules/FrameProviders.lua`) are no client
read and live there, not here: `EllesmereUIUnitFrames_Target`, `EllesmereUIUnitFrames_Focus` and
`EllesmereUIUnitFrames_Pet`, the names EllesmereUIUnitFrames' `EUI_UnitFrames_Init.lua` spawns its
frames under (`ns.Engine.SpawnUnitFrame`), verified identical in the installed Retail (9.8.6) and WoW
Forever (9.8.8) builds on 2026-11-18. It spawns a unit's frame only when that unit's source is
EllesmereUI, at `PLAYER_LOGIN`, which is why the frame anchor looks again on `PLAYER_ENTERING_WORLD`
and `ADDON_LOADED`. `EllesmereUIDB` is never read.

A nameplate's cast bar (`NS.FrameProviders.PlateCastBar`, a nameplate container's Attach to part) is
no client read either and lives beside them: EllesmereUINameplates publishes its namespace as the
global `EllesmereNameplates_NS` (`EllesmereUINameplates.lua`), whose `plates[token]` is its own plate
for a plate token (`EUI_Nameplates_Events.lua` fills it at `NAME_PLATE_UNIT_ADDED` and clears it at
`_REMOVED`), with `.nameplate` the client plate it sits on (`EUI_Nameplates_Plate.lua`'s `SetUnit`)
and `.cast` its cast bar StatusBar (`EUI_Nameplates_PlatePool.lua`). Otherwise the client plate's own
`UnitFrame.castBar` (CompactUnitFrame's key; EllesmereUINameplates' own fallback reads it on both
clients), else `UnitFrame.CastBar`. Verified identical in the installed Retail (9.8.6) and WoW Forever
(9.9) builds of EllesmereUINameplates on 2026-11-20. Every read is a table index under `pcall`, and
a forbidden frame answers nil. With Casts In Front of Nameplates on, EllesmereUI reparents that same
`cast` frame to a `UIParent` frame at `HIGH` (`EllesmereUINameplates_CastOverlay.lua`), so the
anchor holds either way.

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
