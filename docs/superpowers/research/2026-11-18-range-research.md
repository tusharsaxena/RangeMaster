# Range research (2026-11-18)

Research the RangeMaster design rests on. Three sweeps: the installed reference addons
(AppelSwingsForever, RangeDisplay, RangeLens, the vendored LibRangeCheck-3.0), the web
(range addons, Midnight API restrictions, WoW Forever), and the Ka0s standard.

## API facts (Retail 12.1.5, build 70783, Blizzard generated docs)

| API | Secret returns? | Notes |
|---|---|---|
| `C_Spell.IsSpellInRange(spell, unit)` | No | true / false / nil (nil = not applicable). Works in combat. |
| `C_Item.IsItemInRange(item, unit)` | No | Insecure code cannot call it in combat on non-attackable units (10.2.0 rule). Hostile units fine. |
| `CheckInteractDistance(unit, i)` | No | Protected in combat on friendly units since the 10.2 hotfixes; enemies allowed. Index 2 (trade) is unreliable. |
| `UnitInRange(unit)` | **Yes** | Group members only, 40 yd. Not used. |
| `UnitDistanceSquared` | No | Group only, outdoors only. Not used. |
| `C_NamePlate.GetNamePlateForUnit(unit)` | — | Still available; forbidden plates (friendly plates in instances) are not returned. |

Secret-value rules: tainted code may store, concatenate and `SetText` a secret, but cannot compare,
do arithmetic, test it as a boolean or use it as a table key. `UnitGUID` is secret in many contexts,
so caches key on unit tokens. Guard every result with `issecretvalue` and treat secret as unknown.

## WoW Forever (Interface 16001, game type camelot)

- Mainline-family client (C_Spell, C_Item, secret values) on a vanilla world with vanilla spells.
- Detect by interface 16000–19999 or `WOW_PROJECT_CAMELOT`, never by `WOW_PROJECT_ID == 1`.
- Item range checks are reliable only at 20, 30 and 35 yd (AppelSwingsForever Bands.lua:9-17);
  melee spells with 0–0 range report "in range" from any distance; Hunter Auto Shot dead zone 8–35 yd.
- `NAME_PLATE_UNIT_ADDED` can fire before the plate is populated: re-check one frame later
  (RangeLens.lua:1530-1590). Settings proxy controls tainted nameplates on Forever (RangeLens.lua:3805).

## LibRangeCheck-3.0 (GitHub main, MINOR 39)

- Sorted checker lists (spells, items, interact) with a binary search; returns `min, max`
  (`max == nil` past the last checker). Caches per unit token on Midnight.
- `InCombatLockdownRestriction = InCombatLockdown() and not UnitCanAttack("player", unit)`: when
  true it uses the spell-only `*InCombat` lists.
- Forever detected as interface 16000–19999 and served from the Era tables.
- Does not secret-check checker results: wrap calls in `pcall` (RangeDisplay.lua:423).

## Lessons taken from the reference addons

1. Show brackets honestly (`20–25`, `45+`); never invent an exact distance.
2. Unknown is a state of its own (grey `?`), never "out of range".
3. One shared ticker with an adaptive rate; per-tick per-unit memo so N containers cost one check.
4. Repaint only on band change; set text only on text change.
5. Debounced sounds: settle 0.2 s, gap 1 s, silent first band after a unit change
   (AppelSwingsForever BandSounds.lua:87-115).
6. Settle window after a target change so stale answers don't flash.
7. Cursor follow via `GetCursorPosition() / UIParent:GetEffectiveScale()`; mouseover has no clear
   event, so re-validate `UnitExists("mouseover")` each tick (RangeDisplay.lua:479-505).
8. Identify the target's nameplate by comparing plate frames, not `UnitIsUnit` (may be secret).
9. Spells unusable in the current form/stance may report in range from anywhere: only trust
   `IsSpellInRange` for known, usable spells.

Sources: warcraft.wiki.gg (Secret_Values, Patch_12.0.0/API_changes, API pages),
github.com/Gethe/wow-ui-source (live), github.com/WeakAuras/LibRangeCheck-3.0 (PR #59),
curseforge.com (RangeDisplay, Platynator, asRangeDisplay, SimpleRangeFinder, TargetRange),
wowforeverguides.com, github.com/Thunderz96/forever-addon-kit.
