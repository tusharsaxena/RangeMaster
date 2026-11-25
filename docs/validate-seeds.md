# Seed validation — Range Master

The seed-validation contract `/dev-copilot:validate-seeds RangeMaster <flavor>` runs. The command
supplies the loop (clean tree, one date, status, derive, rule, apply, gate, hand-back) and its
standing rules. This file supplies Range Master's procedure: the tool, the files it writes, the
precedent a ruling follows and the nuances of each client. The headings below are the interface the
command reads, so keep their names.

Each run ends in a frozen bundle under `docs/seed-research/<date>-<flavor>/`. The tool is
`tools/seeds/seeds.py`; its docstring is its manual. The first runs are
`docs/seed-research/2026-11-25-retail/` and `docs/seed-research/2026-11-25-forever/`.

**What is validated.** `defaults/SpellSeeds.lua` (`NS.SpellSeeds[client][classFile]`) is
**hand-curated**, not derived: a short list per class of chips, ladder rungs and band-rule anchors.
So a run proposes **no new ids**. It checks every shipped id against the client's own DB2 and
against what the addon's code assumes of that id's range, and every disagreement is a flag.

**What is checked, and the code each check stands for.** The range is SpellMisc `RangeIndex`
(`DifficultyID` 0) into SpellRange: `RangeMin_0`/`RangeMax_0` (hostile) for every list but
`friendly`, which reads `RangeMin_1`/`RangeMax_1`.

| Flag | Applies to | What the code assumes |
| --- | --- | --- |
| `unnamed` | every id | the id exists (`SpellName`) |
| `renamed` | ids a comment in the flavor's block names (`Wing Clip 2974`) | the comment and the build agree |
| `class` | every id | the class can learn it: a `SkillLineAbility` row whose `ClassMask` carries the class, or its `SpellClassOptions` family is the class's (`ChrClasses.SpellClassSet`) |
| `rank` | Forever ids | rank 1 (the spellbook range check reads rank 1, and `Compat.CurrentSpellID` resolves the learned rank by name): no `Rank N` text above 1, no learnable same-family `Rank 1` row of that name, no same-name `SupercedesSpell` |
| `no-range` | every id | the spell has a reach, so `IsSpellInRange` can answer it |
| `ladder-min` | `ladder` | `core/Compat.lua`'s `spellRung` adds a rung only for a max range above 0 with **no min range** |
| `melee-reach` | `anchors.melee` (and the druid's `cat`/`bear`) | no min range, and a reach no farther than `MELEE_REACH_YD` (`modules/Range.lua`; the resolver drops a melee seed past it) |
| `ranged-reach` | `anchors.ranged` | a reach past `MELEE_REACH_YD` |
| `tier-reach` | `anchors.tier<N>` (RangeMaster#20) | the spell reaches exactly N yd: a tier names its yards, and the class preset's band for it ends there |
| `band-reach` | each class's `ranged`, `friendly` and `tier<N>` roles | the longest reach the role has (the anchor `longerFirst` puts first) is the far edge of the band the class's default preset gives that role (`defaults/BandSetPresets.lua`: the class's own `<CLASS>_BY_CLIENT` list for the flavor, else Melee / Ranged; `friendly` against the Healer preset), and a tier anchor's min range is no farther than its band's near edge (Charge's 8 yd under an 8-25 CHARGE band). Past that reach the anchor says false and `beyond` reads OOR, whatever the band's yards say |
| `unseeded` | a role the class's default preset asks (key id `0`) | the class has an anchor list for it; a band asking a role with none only ever reads its yards |
| `gap-fit` | a class whose default preset has a gap band (the Forever hunter) | every min-range ranged anchor's min is the gap's far edge, every melee anchor's reach its near edge, and at least one ranged anchor has a min range (`Range.Near`) |

The chips have no band of their own: a chip is asked "in range?" and shows the answer. The DIFF
table still shows where each chip's reach falls in the class's default preset, and a chip that is
also a rung or an anchor is checked as one.

## Flavors

| Flavor | Source | Seed files | Tools |
| --- | --- | --- | --- |
| `retail` | wago.tools product `wow` (Retail live) | `defaults/SpellSeeds.lua`, the `retail` block (hand-curated, tool-checked) | `tools/seeds/seeds.py` |
| `forever` | wago.tools product `wowf` (WoW Forever live) | `defaults/SpellSeeds.lua`, the `forever` block (hand-curated, tool-checked) | `tools/seeds/seeds.py` |

Range Master serves Retail and WoW Forever (the roster's Clients column), so both flavors run.

## Rules

- **Only the tool removes a list's ids.** `seeds.py apply` removes every id ruled `remove` from its
  class's list in that flavor's block. The file's comments, including its header's re-validation
  line, are hand-written and rolled by hand under `### After`. A replacement id, when a ruling calls
  for one, is added by hand under `### After`, with its own row in the next run.
- **Rulings are data.** They live in `tools/seeds/retail_rulings.json` and
  `tools/seeds/forever_rulings.json`, written only by `seeds.py rule`. A key is
  `shipped:<kind>:<CLASS>.<list>:<id>`; the list is `chips`, `ladder`, `melee`, `melee.cat`,
  `melee.bear`, `ranged`, `friendly` or a tier (`tier10`, `tier13`, `tier15`, `tier20`, `tier25`,
  `tier30`). An id flag (`unnamed`, `renamed`, `class`, `rank`, `no-range`, `ladder-min`, `melee-reach`,
  `ranged-reach`, `tier-reach`) is ruled `keep` or `remove`. A role flag (`band-reach`, `gap-fit`,
  `unseeded`) is ruled `keep`: it is about a preset's yards, which the tool never writes, and a change
  there is the owner's. A ruling is never keyed by build: it holds until the thing it ruled on stops
  being proposed.
- **Precedent, in this order, never re-litigated:**
  1. a ruling already in the flavor's rulings file;
  2. the owner's rulings recorded in the code: **Wing Clip 2974 is the Forever hunter's melee anchor**,
     and Raptor Strike 2973 and Attack 6603 have no range requirement on WoW Forever (they answer in
     range at any distance), so neither comes back (`defaults/SpellSeeds.lua`, the owner, 2026-11-24;
     `tests/test_range.lua` pins it); no Mongoose Bite (reactive) and no Hunter's Mark band; Disrupt
     183752 is a melee anchor and a chip, never a rung; Holy Strike 679 is the Forever paladin's
     melee anchor;
  3. the owner's rulings in `modules/BandSets.lua`'s header (2026-11-19): a spell band's anchor out
     of range past its reach reads OOR whatever its fallback yards say, and an Evoker's 25-30 yd
     friend is not NEAR when Living Flame cannot reach. A `band-reach` flag is therefore kept unless
     a seed with a longer reach exists for that class on that client;
  4. `docs/common-tasks.md`, *Add a seed spell or a ladder rung*: a melee or min-range spell belongs
     in `chips`, not `ladder`; a melee anchor never reaches past 8 yd; never a reactive spell.
- **What `remove` means here.** Remove an id that the code can never use in that list (a
  `ladder-min` rung, a `melee-reach` anchor), that the build does not have (`unnamed`) or that the
  class cannot learn (`class`). Replace it by hand when a fitting id exists, citing the DB2 row.
- **When the data cannot decide** (a spell whose targeting the tables do not show, a talent that
  moves a reach), rule `keep` with `needs owner review: <why>`, or `remove` with the evidence and list
  it in the bundle's `ANALYSIS.md` under *Judgment calls applied*, so the owner can reverse it at
  smoke.
- **Evidence.** The bundle's `raw/*.csv.gz`, `candidates.json` (a `verdicts` row per shipped id and
  list, with its name, rank text, range row, min, max, band and class verdict) and `DIFF.md`.
- **Privacy.** No player name, realm or GUID goes into a bundle, a ruling or a commit.

## Flavor: retail

### Status

```sh
python3 tools/seeds/seeds.py status --flavor retail
```

Prints `CURRENT <build> (<bundle>)`, or `NEW <build> (last ruled <build>, <bundle>)`, comparing the
newest live (non-bgdl) `wow` build with the newest `*-retail` bundle.

### Freeze and derive

```sh
python3 tools/seeds/seeds.py derive --flavor retail --bundle docs/seed-research/<date>-retail --date <date> --build <build>
```

It pins `<build>`, fetches six tables (about 60 MB, most of it `SpellMisc`) into the git-ignored
`tools/seeds/.cache/`, and freezes them gzipped (about 9 MB) into the bundle's `raw/`. It writes
`SOURCES.md`, `DIFF.md` and `candidates.json`. `--replay` re-derives from the bundle's own `raw/` with
no network, byte for byte. **If the sentinel gate fails** (Frostbolt 116, Fireball 133 or Wrath 5176
without a name and a range, or SpellRange 2 not 5 yd), **stop**: the tables have moved, and the fix
is in the tool. Report the class and id counts, the flag counts by kind and the unruled count.

### Rule

```sh
python3 tools/seeds/seeds.py check --flavor retail --bundle docs/seed-research/<date>-retail
python3 tools/seeds/seeds.py rule  --flavor retail --tsv <scratchpad>/rulings.tsv --bundle docs/seed-research/<date>-retail
```

`check` lists every unruled key with why it was flagged and exits 1 while there is one. It must print
`OK` after `rule`. The TSV holds one `key<TAB>ruling<TAB>reason` line per key. Retail's ladder is
never walked (LibRangeCheck answers there), so a Retail `ladder-min` changes nothing a player sees;
it is still removed, so the list says what the code does.

### Apply

```sh
python3 tools/seeds/seeds.py report --flavor retail --bundle docs/seed-research/<date>-retail --date <date>
python3 tools/seeds/seeds.py apply  --flavor retail --bundle docs/seed-research/<date>-retail --date <date>
```

`report` comes before `apply`, because once an id has been removed a re-derive no longer flags it.
`apply` refuses while anything is unruled, removes only the `retail` block's ruled ids, keeps the
file's CRLF and every other byte, and a second `apply` changes nothing.

### After

- Roll the re-validation line in `defaults/SpellSeeds.lua`'s header: both flavors' builds, the date,
  the bundles. Add a comment beside a list a removal emptied or changed the meaning of.
- When an id left or joined a list, roll the pins in `tests/test_range.lua` (*no ladder seed is a
  min-range spell*, *the anchors carry the critic's corrections*).
- Write the bundle's `ANALYSIS.md` by hand: what was checked, the flags and their rulings, and a
  *Judgment calls applied* section naming every shipped-data change with its evidence. A run that
  changes nothing still says so.
- For each shipped-data change, add a smoke check to `docs/smoke-tests.md`'s *Range engine* theme
  (the next free `RANGE-<n>`, after RANGE-18), with its *Pending sign-off* row. A run that changes
  nothing adds none.

### Stage

`defaults/SpellSeeds.lua`, `tools/seeds/retail_rulings.json`, `docs/seed-research/<date>-retail`, plus
any test, smoke, doc or citation edits. Commit message:
`Seeds (retail): re-validated against <build> (<date>)`.

## Flavor: forever

### Status

```sh
python3 tools/seeds/seeds.py status --flavor forever
```

The same as Retail's, against the newest live `wowf` build and the newest `*-forever` bundle.

### Freeze and derive

```sh
python3 tools/seeds/seeds.py derive --flavor forever --bundle docs/seed-research/<date>-forever --date <date> --build <build>
```

It fetches the six Retail tables plus `Spell` (for `NameSubtext_lang`, the rank text), about 7 MB,
and freezes them (about 1.3 MB). The sentinel gate is Retail's. The `rank` flag runs on this flavor
only: Forever keeps each vanilla rank as its own id (clients-§10).

### Rule

```sh
python3 tools/seeds/seeds.py check --flavor forever --bundle docs/seed-research/<date>-forever
python3 tools/seeds/seeds.py rule  --flavor forever --tsv <scratchpad>/rulings.tsv --bundle docs/seed-research/<date>-forever
```

Forever's ladder **is** walked when LibRangeCheck has no answer, so a `ladder-min` there is a rung the
player was promised and never got. A `rank` flag is the one Forever check whose answer the game
gives more reliably than the tables: a "Rank 1" row with no learn row (a proc, a rune) is not a rank,
and the tool already skips it.

### Apply

```sh
python3 tools/seeds/seeds.py report --flavor forever --bundle docs/seed-research/<date>-forever --date <date>
python3 tools/seeds/seeds.py apply  --flavor forever --bundle docs/seed-research/<date>-forever --date <date>
```

As Retail's, on the `forever` block only.

### After

As Retail's. A Forever ladder change also checks `docs/smoke-tests.md` RANGE-3 (the Forever ladder's
edges) still reads true.

### Stage

`defaults/SpellSeeds.lua`, `tools/seeds/forever_rulings.json`, `docs/seed-research/<date>-forever`,
plus any test, smoke, doc or citation edits. Commit message:
`Seeds (forever): re-validated against <build> (<date>)`.

## Gate

```sh
~/.claude/dev-copilot/bin/ka0s-bounded lua tests/run.lua
KA0S_KIT_CLIENT=forever ~/.claude/dev-copilot/bin/ka0s-bounded lua tests/run.lua
~/.claude/dev-copilot/bin/ka0s-bounded luacheck .
python3 -m pytest -q -p no:cacheprovider tools/seeds
```

luacheck must report 0 warnings and 0 errors, and every suite 0 failed. Range Master serves Retail
and WoW Forever, so the headless suite runs under both kit profiles (clients-§6).

## Notes

- **The tier anchors' first check (RangeMaster#20, 2026-11-25).** The class presets and the `tier<N>`
  lists came after the two first-run bundles were frozen, so they were checked by a `derive --replay`
  of those bundles' own `raw/` tables into a scratch copy (the frozen bundles were left as they are):
  every tier id exists, is its class's, is rank 1 on Forever and reaches its tier's yards; the
  per-class presets removed the 14 `band-reach` flags the generic presets' 40 yd edges raised (the
  old rulings stay as provenance), and the one flag left on each flavor is an existing `keep`
  (Retail's Evoker and Forever's mage `friendly` under Healer). `check` read OK on both. The next
  run on a new build writes the tiers into its own bundle.
- **DB2 says the base reach.** A talent (Hawk Eye, Flame Throwing) lengthens a reach the client then
  reports (`docs/smoke-tests.md` RANGE-6), and DB2 knows nothing of it. A `band-reach` flag on a
  class whose talents close the gap is still a flag: the untalented player sees it.
- **DB2 does not say how a spell is aimed.** An area cast placed with a targeting circle (Distract)
  has a range row like any other, and a unit range check is not expected to answer it. The tool
  cannot tell; the ruling says so.
- **No ForeverDB step.** Every fact this contract checks is a spell's, which the client's DB2 holds.
  ForeverDB adds server-side facts (creatures, spawns, vendors), none of which a Range Master seed is.
- **The prose gate and game data.** A bundle's generated `DIFF.md` quotes the client's own spell
  names, and WoW Forever spells one of them, spell 20271, the British way. The kit's US-English gate
  (`tests/_kit/test_prose.lua`) flags it, so each bundle that quotes it gets its own per-file,
  per-word entry in `tests/prose_waivers.lua`; the name is never respelled.
- **Bundle size.** A Retail bundle's `raw/` is about 9 MB, most of it `SpellMisc` and `SpellName`; a
  Forever one about 1.3 MB.
- **A ruling outlives its flag.** After `apply`, a removed id stops being flagged. Its ruling stays in
  the file as provenance, and that is not an error.
- **The shared helper.** Whether the build pin, the cache, the bundle and the rulings move into a
  shared helper is LibKa0s#91. Until it decides, the tool copies DPS Race's and Aura Master's patterns
  and imports nothing across repos.
