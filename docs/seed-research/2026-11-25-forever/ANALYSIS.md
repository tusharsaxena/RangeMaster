# Analysis — seed validation, 2026-11-25 (forever, wowf 1.60.1.71091)

Hand-written. The first run of `docs/validate-seeds.md` on the `forever` flavor (item SF-RM-01 of
Ka0sAddonsCommonTasks `docs/2026-11-25-SEEDS_AND_FOREVERDB/`). The build is the newest live, non-bgdl
`wowf` build the builds API listed on 2026-11-25, resolved once for this run.

## What was checked

`defaults/SpellSeeds.lua`'s `forever` block: 9 classes, 95 ids across their chips, ladder and anchor
lists. Every id was checked for existence, class, rank 1 and range, and each list's range against
what the code asks of it (the contract's *What is checked* table): `MELEE_REACH_YD` is 8, each
class's default preset is read from `defaults/BandSetPresets.lua` (the Forever hunter's is
`hunter.forever`: 0-5 MELEE, 5-8 DEAD gap, 8-35 RANGE, 35+ OOR).

## What the build says

- **Every id exists, and every one is its class's** (95 of 95 `ok`: a learn row's `ClassMask`, or the
  class's own family). Throw 2764 and the three Shoot spells are another family's in
  `SpellClassOptions` (8 and 9), but their `SkillLineAbility` rows carry the warrior and rogue bits.
- **Every id is rank 1, or has no rank.** One heuristic hit was a false positive and was fixed in the
  tool rather than ruled: a second `Stormstrike` row, 410156, reads "Rank 1", but it has no learn row
  (it is the talent's extra-attack proc), and Stormstrike 17364 is what the `Talent` table grants. The
  tool now counts only learnable rows as ranks.
- **Every melee anchor is SpellRange 2, Combat Range, 0-5 yd** (14 ids, druid forms included), so none
  is dropped by the 8 yd reach guard. Wing Clip 2974 is among them; the owner's ruling (2026-11-24)
  stands and was not re-examined.
- **The Forever hunter's dead zone fits.** Auto Shot 75, Arcane Shot 3044 and Serpent Sting 1978 are
  SpellRange 114, Hunter Range, 8-35: the min range is the gap's far edge (8) and the reach is the OOR
  edge (35). Wing Clip reaches 5, the gap's near edge. No `gap-fit` flag.
- **Two ladder seeds can never be rungs.** Throw 2764 (SpellRange 74, Ranged Weapon, 8-30) is the
  whole ladder of the warrior and of the rogue. `core/Compat.lua`'s `spellRung` adds a rung only for a
  spell with no min range, so neither ladder ever added one. RANGE-3 already records a fresh warrior's
  edges as the item and interact rungs alone.
- **Nine roles reach short of their band's far edge** (`band-reach`): the warrior, rogue, paladin,
  druid and shaman ranged roles at 30 yd under Melee / Ranged's LONG 30-40; the mage at 35 and the
  priest and warlock at 30 under Caster 40's CAST 8-40; the mage's friendly Arcane Intellect at 30
  under Healer's FAR 30-40. On a vanilla world no seed of those classes reaches 40, so past 30 (35)
  yd the anchor says false and the set reads OOR, whatever the LONG, CAST or FAR yards say.

## Rulings

- `ladder-min` WARRIOR.ladder 2764 and ROGUE.ladder 2764: **remove** (both shipped-data changes are
  listed below).
- `band-reach`, 9 flags: **keep**, by precedent: the owner's ruling of 2026-11-19 in
  `modules/BandSets.lua`'s header, "a 30 yd spell out of range reads OOR, not unknown". The preset's
  yards are its fallback, and no longer-reaching seed exists to fix it with. A per-client Caster 40 or
  Melee / Ranged set (as the Hunter set already is) would change what the bands *say*; that is a
  preset design question, not a seed one, and the data cannot decide it. **Needs owner review**, if
  the owner wants the Forever presets' yards to match a 30 yd world.

## Judgment calls applied

Each is a shipped-data change in `defaults/SpellSeeds.lua`, with a smoke row in
`docs/smoke-tests.md`. Reverse any of them by putting the id back.

| Change | Evidence | Why a judgment call | Smoke |
| --- | --- | --- | --- |
| `forever.WARRIOR.ladder`: `{ 2764 }` to `{}` | Throw 2764, SpellMisc RangeIndex 74, SpellRange 74 "Ranged Weapon" `RangeMin_0` 8, `RangeMax_0` 30; `spellRung` refuses a min range; `docs/common-tasks.md` puts a min-range spell in chips | removed, not replaced: no learnable warrior seed has no min range and a reach past melee. No runtime change: the rung was never added | RANGE-19 |
| `forever.ROGUE.ladder`: `{ 2764 }` to `{}` | as above | removed, not replaced: the one 0-30 rogue seed, Distract 1725, is an area cast placed with a targeting circle (game knowledge; these tables do not show targeting), so a unit range check is not expected to answer it. No runtime change | RANGE-20 |

Throw stays a warrior and rogue chip and a ranged anchor, where a min range is what the code expects.

## What a later run should re-check

- Whether a Forever patch gives a class a ranged spell with no min range that a ladder could use (a
  ladder that no longer lists Throw cannot flag it: look at the DIFF's chips and ranged rows).
- **Needs owner review:** `forever.ROGUE.anchors.ranged` keeps Distract 1725 (0-30, no min range). It is
  an area cast placed with a targeting circle (game knowledge; these tables do not show targeting), so a
  unit range check may never answer it in range, and the data cannot decide whether it earns its place
  as an anchor. The data is unchanged; the owner rules whether it stays.
- Whether the owner reshapes the Forever presets' yards (the nine `band-reach` keeps would then fall
  away or move).
