Delta: LibKa0s v1.107.0 -> v1.108.0

Recorded before the commit. Payload taken from the tag, never the sibling tree: `git -C ../LibKa0s archive v1.108.0 LibKa0s testkit tools` (tag commit 56c20b76, a local tag on the library's branch `feat/2026-11-20-libka0s-94-97-99-100`, not on origin yet: `git -C ../LibKa0s ls-remote --tags origin v1.108.0` prints nothing). Run under Ka0sAddonsCommonTasks `docs/2026-11-20-LIBKA0S_94_97_99_100/`, item SD-RV-RM: copy and bundle only, no adoption interview and no issue filing (the run's items for this addon are pre-decided: SD-RV-RM and SD-SK-RM).

## Step 0 pre-flight
No `docs/revendor/` store before this bundle, so there is no newest bundle to check: "no store". This bundle opens the store.

## 3a Base
- `grep -n '[Bb]undles' CLAUDE.md` named v1.107.0 before the roll (CLAUDE.md, last section).
- Last payload commit, `git log -1 --format=%h -- libs/LibKa0s tests/_kit`, is c56ef85 ("AF-RV-RM: Re-vendor the re-cut LibKa0s v1.107.0"); its CLAUDE.md names v1.107.0. They agree.
- Payload before the copy equalled the library at v1.107.0: `diff -rq --strip-trailing-cr` of `libs/LibKa0s` (outside the pruned `media/icons` and `media/sounds`) and of `tests/_kit` against a v1.107.0 extract printed nothing.
- `git -C ../LibKa0s log --oneline v1.107.0..v1.108.0`: 15 commits (SD-LK-94, SD-LK-99, SD-LK-100, SD-LK-97 Batches A to D, SD-LK-GUARD and SD-LK-REL, with their review fixes). `git -C ../LibKa0s diff --stat v1.107.0 v1.108.0 -- LibKa0s testkit`: 23 files changed, 1363 insertions, 306 deletions.

## 3b/3c Per-file minors that moved (old = this addon before the copy, new = v1.108.0)
The constants this addon carried matched v1.107.0's, so the line and the bytes agreed.
```
Core.lua                   old: 18  new: 19
Callout.lua                old: 4   new: 5
CalloutSettings.lua        old: 5   new: 6
WaypointArrow.lua          old: 2   new: 3
WaypointArrowSettings.lua  old: 2   new: 3
Charts.lua                 old: 2   new: 3
ChartsRender.lua           old: 1   new: 2
SkinPaint.lua              old: 19  new: 20
SkinPaintHud.lua           old: 1   new: 2
SkinPaintControls.lua      old: 18  new: 19
Widgets.lua                old: 29  new: 30
WidgetsDropdown.lua        old: 2   new: 3
WidgetsDragHandle.lua      old: 15  new: 16
WidgetsDragHandleTip.lua   old: 2   new: 3
WidgetsLineChart.lua       old: 7   new: 8
WidgetsBar.lua             old: 1   new: 2
OptionsCompose.lua         old: 19  new: 20
```
Every other file kept its minor. No file is new and no `NEEDS_*` floor rose.

## 3d Diffs
Before the prune, `diff -r` of both payloads against the v1.108.0 extract was empty. After the prune the only lines are `Only in <extract>/LibKa0s/media/icons...` and `Only in <extract>/LibKa0s/media/sounds...` (names not declared).

## 3e Consumption map
Of the majors that moved, this addon calls:
- **Options** (OptionsCompose minor 20): `H.BorderGroup` once, `H.ColorPair` twice and `H.FontGroup` three times, all in `settings/Containers_Display.lua` (the Frame, Number, Text, Label and Dot tabs). These are the release's consumer-visible default change.
- **Widgets**: `W.Bar` with `W.BarStyle("mini")` (`modules/Elements_Indicator.lua`, the Bar shape of the dot), `KW.DragHandle` (`modules/Anchors_Screen.lua`), `KW.TestStrip` and `KW.DockTestStrip` (`modules/Container.lua`), `KW.Dropdown`, `KW.Footer` and `KW.HeaderButtons` (`settings/Presets.lua`, the preset picker), `W.ReorderList` (the element order).
- **Skin** (SkinPaint, SkinPaintHud, SkinPaintControls) through `NS.Skin`, and **Core** through `NS.ApplySkin(frame, keys)` with no `skinBands`.
- No Callout, WaypointArrow, Charts or `S.ApplyBarFill`.

## 3f Kit revision
```
old: tests/_kit/framework.lua:20:Kit.VERSION = 57
new: testkit/framework.lua:20:Kit.VERSION = 58
```
Both payloads copied whole in one commit, as the pairing rule requires. CLAUDE.md carries no kit sentence, so only the provenance line rolls.

## 3g Contract delta and Blockers
`grep -rn '__Attach[A-Za-z]*\|__releaseChrome' core modules settings tests` outside `_kit`: none.
- OptionsCompose minor 20 emits each block's skin companions unless the host passes `fromSkin = false`. A container is not an AceDB default (`defaults/Profile.lua`, `NS.CONTAINER_TEMPLATE`), so the new rows' paths resolved to nothing and the schema suites went red (13 unresolved paths, the row-list pins on the Frame, Dot and Label tabs). Fixed in the re-vendor commit by passing `fromSkin = false` on the six blocks, minor 19's blocks byte for byte, until SD-SK-RM adds the companions to the template, draws them and moves the stored containers once.
- `W.BarStyle`'s `borderFromSkin` and `glossFromSkin` now default true: the Bar dot draws a skin's real `bar.borderStyle` and the Glass gloss (SD-LK-97.2, 97.3). This is the look the audit asked for; DRAW-6 is its smoke check.
- Kit revision 58: the typed-value scanner reads two new hits, both rows with a kit category (05_SUMMARY.md). The skin-switch family checks pass on the three declared surfaces.

**Blockers: none.**

## 3h Unrecorded vendored tags
No bundle in the store before this one, so there is no horizon and nothing to back-fill (the command's 3h: a store with no bundle is measured from this run on). No span bundle.

## 3i Icon declaration
- `grep -n 'LibKa0s icons:' CLAUDE.md`: the line directly under the provenance line, kept as written (13 names). The release draws no new library icon for a surface this addon wires.
- `lua <extract>/tools/prune-icons.lua .`: icons pruned back to the 13 declared names plus the Open Iconic license; the sounds prune (no `LibKa0s sounds:` line) removed 362 files.

## 3j Tests that assume the whole icon folder
```
tests/test_mediasetup.lua:144   io.open over the declared names only
tests/test_optionssetup.lua:433 io.open("libs/LibKa0s/media/icons/info.tga")   (a declared name)
```
No whole-catalog loop. Nothing to fix.
