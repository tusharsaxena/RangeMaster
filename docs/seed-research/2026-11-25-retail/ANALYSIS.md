# Analysis — seed validation, 2026-11-25 (retail, wow 12.1.5.70961)

Hand-written. The first run of `docs/validate-seeds.md` on the `retail` flavor (item SF-RM-01 of
Ka0sAddonsCommonTasks `docs/2026-11-25-SEEDS_AND_FOREVERDB/`). The build is the newest live, non-bgdl
`wow` build the builds API listed on 2026-11-25, resolved once for this run.

## What was checked

`defaults/SpellSeeds.lua`'s `retail` block: 13 classes, 141 ids across their chips, ladder and anchor
lists. Every id was checked for existence, class and range, and each list's range against what the
code asks of it (the contract's *What is checked* table): `MELEE_REACH_YD` is 8, each class's default
preset is read from `defaults/BandSetPresets.lua` (Retail's hunter is `hunter.retail`: 0-5 MELEE,
5-40 RANGED, 40+ OOR; no gap). The rank check is Forever's only.

## What the build says

- **Every id exists, and every one is its class's** (141 of 141 `ok`). Many spec and talent spells
  (Raptor Strike 186270, Avenger's Shield 31935, Cobra Shot 193455, and others) have no learn row on
  Retail; their family is the class's.
- **The comments' names agree** with the build for every id they name (Holy Fire 14914, Healing Wave
  77472, Disrupt 183752, Fracture 263642, Shear 203782, Soul Cleave 228477, Reap 1226019).
- **Every melee anchor is SpellRange 2, Combat Range, 0-5 yd** (26 ids), Disrupt 183752 included,
  which matches the file's note that it is 0-5 in 12.1.5 and not the 20 yd LibRangeCheck labels it.
- **One ladder seed can never be a rung.** Heroic Throw 57755 is SpellRange 288, "Large Minimum Range
  (8-30)". `core/Compat.lua`'s `spellRung` adds a rung only for a spell with no min range, and Retail
  never walks the ladder at all (LibRangeCheck answers there), so it was dead twice over.
- **Seven roles reach short of their band's far edge** (`band-reach`): the warrior, paladin, rogue,
  death knight and demon hunter ranged roles at 30 yd under Melee / Ranged's LONG 30-40; the Evoker's
  ranged role at 25 under Caster 40's CAST 8-40 and its friendly Living Flame at 25 under Healer's FAR
  30-40. Hunter, mage, priest, warlock, shaman, monk and druid reach 40.

## Rulings

- `ladder-min` WARRIOR.ladder 57755: **remove** (the shipped-data change is listed below).
- `band-reach`, 7 flags: **keep**, by precedent. Six cite the owner's ruling of 2026-11-19 in
  `modules/BandSets.lua`'s header ("a 30 yd spell out of range reads OOR, not unknown"); the Evoker's
  friendly cites the same day's ruling that an Evoker's 25-30 yd friend is not NEAR when Living Flame
  cannot reach. No longer-reaching seed exists for these classes; the presets' yards are a design
  question the data cannot decide.

## Judgment calls applied

The one shipped-data change in `defaults/SpellSeeds.lua`, with a smoke row in `docs/smoke-tests.md`.
Reverse it by putting the id back.

| Change | Evidence | Why a judgment call | Smoke |
| --- | --- | --- | --- |
| `retail.WARRIOR.ladder`: `{ 57755, 355 }` to `{ 355 }` | Heroic Throw 57755, SpellMisc RangeIndex 288, SpellRange 288 `RangeMin_0` 8, `RangeMax_0` 30; `spellRung` refuses a min range; `docs/common-tasks.md` puts a min-range spell in chips | removed, not replaced: Taunt 355 (SpellRange 4, 0-30) is already the 30 yd rung. No runtime change: Retail never builds a ladder | RANGE-21 |

Heroic Throw stays a warrior chip and its first ranged anchor.

## What a later run should re-check

- Whether a talent or a patch moves a 30 yd role to 40 (its `band-reach` keep would fall away).
- Disrupt 183752's range: the file's note expects Improved Disrupt to report 10 yd and the melee guard
  to skip it; a base-range change in DB2 would show as a `melee-reach` flag.
