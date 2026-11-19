# Plan: five presets, indicator styles, Display tabs, frame defaults (2026-11-19)

Branch `feat/2026-11-19-presets-dot-styles` (off `master` at `cb7ca0a`). Push after each milestone;
merge only on the owner's go-ahead. Resumable: the ledger below is the checkpoint. A milestone is done
when its row reads **done** with its commit, and the green gate passed at that commit:
`lua tests/run.lua`, `KA0S_KIT_CLIENT=forever lua tests/run.lua`,
`~/.claude/dev-copilot/bin/ka0s-bounded luacheck .` (0/0). Every `.lua`/`.md` file is CRLF.

The owner's rulings for this run (2026-11-19):
- Presets: Simple (dot only), Intermediate (Range Text: text only), Intermediate (Range Numbers:
  number only), Advanced (dot + number + text), Expert (dot + number + text + spell chips). All five
  put target, focus, pet and mouseover FREE ON SCREEN at the preset homes (`Presets.HOME`), Simple's
  arrangement. Expert also keeps the old Advanced extras: the target-plate and all-nameplates
  containers (homes `targetPlate`, `nameplates`), the out-of-range sound on target, the Healer
  friendly band set on target, focus and mouseover.
- Indicator art: shapes dot, ring, square, diamond, triangle, hexagon (new), star (new); styles
  plain, matte, glossy, glowing, neon, gem; **matte is the default**. White art with a transparent
  background, tinted by SetVertexColor. Drawn by a script in the repo (no third-party art). Bar and
  Spell icon stay shapes and take no style.
- Settings: Containers > Display gains a **Dot** tab (moved from Indicator > Indicator) and a **Spell
  chips** tab (moved from Indicator > Spell chips); the Indicator rail entry goes. The Dot tab: Show
  dot, Shape, Style (pick shape, then style), Size, color + color mode. NO preview box on the tab.
- Default container look: background on, border on, a new **Border opacity** setting at 25%.
- Existing containers keep their look: a one-time migration (schemaVersion step 1) writes border
  opacity 100% and indicator style `plain` onto every container already stored, in every profile.
- The mockup the owner approved: https://claude.ai/artifact/TNusrMdzoqQwA377b9GTL8 (its Shapes x
  styles board; the Dot tab board minus the preview).

## Ledger

| # | Milestone | Status | Commit |
|---|---|---|---|
| M0 | Pending work committed (#17 re-vendor; preview nameplate, position rows, preset homes) | done | `9ef8147`, `54c086b` |
| M1 | Indicator art and styles | done | `d3a76e2` |
| M2 | Frame defaults: border opacity, background on, migration step 1 | done | `63f8df8` |
| M3 | Display tabs: Dot and Spell chips moved, Indicator entry removed | done | `f497230` |
| M4 | The five presets | done | `b80fa90` |
| M5 | Review: parallel reviewers, adversarially verified, fixes | done | `2c6518c` |
| M6 | Docs sweep, test-case list, badge, gate, push | done | `5d735d9` |
| M7 | Display > Label tab: a name caption on each container | done | `799130d` |
| M8 | Band preview blocks removed from the settings | done | `f320b14` |
| M9 | Halo-free styles drawn at the old art's fill | done | `66db5e5` |
| M10 | Review of M7-M9, fixes, docs, push | pending | |

## M1. Indicator art and styles

- `tools/indicator_art.py` (Python 3 + Pillow): draws every shape x style as a 128x128 32-bit TGA,
  white/grayscale RGB with real alpha (supersampled, then downsampled, for clean edges), into
  `media/textures/indicators/<shape>_<style>.tga`. Deterministic (same bytes on every run). The
  styles follow the mockup: plain = flat white; matte = radial light-gray shading with a soft dark
  rim, no highlight; glossy = top-to-bottom gradient with a clipped white shine on the upper half;
  glowing = solid with a soft blurred halo; neon = a bright outline with a blurred glow, faint fill;
  gem = two hard facets, light upper-left, dark lower-right, thin light edge. Leave room inside the
  128 box for halos (shape about 70% of the box) so nothing clips.
- The five old single files (`dot.tga` ... `triangle.tga`) are removed; nothing else may name them.
- `.pkgmeta`: `tools` ignored (dev-only). `.gitattributes`: `*.tga` binary (check it already is).
- `defaults/Profile.lua`: `elements.indicator.style = "matte"`; shapes list gains hexagon, star.
- `modules/Elements_Indicator.lua`: the texture is `C.INDICATOR_PATH .. shape .. "_" .. style`, an
  unknown shape falling back to dot and an unknown style to matte; bar and icon ignore style.
- Tests: every shape x style file exists on disk with the TGA header of a 128x128 32-bit image; the
  element picks the right path for a stored shape/style and the fallbacks; red under the old path.

## M2. Frame defaults and the migration

- `defaults/Profile.lua`: `frame.border.alpha = 0.25` (new field), `frame.background.enabled = true`.
- `modules/Container.lua` (Paint): the border's alpha multiplied by `frame.border.alpha` in every
  color mode (band, fixed, class), clamped 0..1.
- `settings/Containers_Display.lua`: a **Border opacity** slider (0..1, percent, step 0.05) in the
  Frame tab's Border subgroup, after the color pair.
- `core/Database.lua`: SCHEMA_STEPS gains step `to = 1`: for every stored profile (AceDB's
  `db.profiles` / the raw `RangeMasterDB.profiles`, and the active profile), every container already
  stored gets `frame.border.alpha = 1` and `elements.indicator.style = "plain"` where unset.
  Idempotent; a fresh profile has no containers, so new ones get the defaults. `NS.SCHEMA_VERSION`
  follows.
- Tests: the migration writes both fields on an old profile's containers, leaves a new container's
  defaults alone, and runs once; the border paints at 25% by default and 100% after migration.

## M3. Display tabs

- `settings/Containers_Display.lua` tabs, in order: Layout, Frame, Number, Text, Dot, Spell chips.
- Dot tab: Show dot; Shape (dropdown: Dot, Ring, Square, Diamond, Triangle, Hexagon, Star, Bar, Spell
  icon); Style (dropdown: Plain, Matte, Glossy, Glowing, Neon, Gem; disabled while the shape is bar or
  icon); Size; the color pair. A visual tile picker for Style (each tile drawn with the stored shape
  in that style), as the mockup shows, is welcome if it fits the page's renderer the way the element
  order list does; the dropdown row stays in the schema either way, so `/rm set` reaches it.
- Spell chips tab: the three rows from `settings/Containers_Indicator.lua`, unchanged paths.
- `settings/Containers_Indicator.lua` deleted (and from the TOC and test load lists); the rail lists
  General, Display, Visibility, Sounds. The element order list calls the indicator "Dot".
- Tests: the rows' new page/group, the rail without Indicator, Style disabled for bar and icon.

## M4. The five presets

- `modules/Presets.lua`: ORDER `simple, text, numbers, advanced, expert`; names Simple,
  Intermediate (Range Text), Intermediate (Range Numbers), Advanced, Expert; every container at its
  home, free on screen, with the M2 frame defaults and the matte dot. Expert's extras as ruled.
- `settings/Presets.lua`: the picker's dropdown and blurbs for five; the General > Presets tab's
  cards; `/rm preset <key>`; the `N containers` counts right (Expert 6).
- Tests: each preset's elements, placement and count; Expert's extras; the picker lists five.

## M5. Review

Parallel reviewers over the branch diff (correctness and edge cases; standard conformance per
`CLAUDE.md`; tests and docs), each finding adversarially verified, then one fix pass.

## M6. Wrap-up

Every doc that names the old presets, the Indicator entry, the old art or the old defaults
(`docs/settings-panel.md`, `docs/smoke-tests.md`, `docs/data-flow.md`, `docs/module-map.md`,
`docs/schema.md`, `README.md`), `docs/test-cases.md` regenerated
(`lua tests/run.lua --list`), the README test badge, the gate, push.

## Added 2026-11-19, after M6 (the owner's requests during the run)

### M7. Display > Label tab

A caption naming the display (the owner: "where can I set the container labels, decide where to show
them and select text styling options"). New container fields under `label`:
`enabled` (default false, so no stored container changes and no migration is needed), `text` (""
means the container's name, the Name row on General), `position` (`top`, `bottom`, `left`, `right`:
outside the elements but INSIDE the root, so the root's size includes it and the drag strip and the
preview strips, which sit on the root's top edge, clear it), `align` (`left`, `center`, `right` for
top/bottom), `gap` (px between caption and elements), and the font block the Number and Text tabs
use (font, size, outline, shadow) plus a color pair (`color`, `colorMode`: band / fixed / class, as
the other elements). Drawn by `modules/Container.lua` as a FontString on the root's overlay, laid out
in `Instance:Layout` with the cells (a fixed-size container keeps its box: the caption goes inside it
as well). A Label tab in Containers > Display after Text, rows in the order above; the Text row's
EditBox applies on Enter. Tests: the caption's text (name fallback, own text), each position's
placement and the root's grown size, hidden while disabled, the color modes.

### M8. Band preview blocks removed

Remove the band preview from the settings wherever it shows: Containers > General's Preview section
(`settings/Containers.lua` renderPreview and its strings) and the band ribbon over the Bands list on
the Band sets page (`settings/BandSets.lua` renderBands). `/rm bands` keeps its chat line (command
output, not a settings preview). Delete strings nothing uses; `NS.BandRibbon` stays only if something
still calls it. Tests and docs that named the preview follow.

### M9. Halo-free styles at the old fill

M1 draws every shape at about 70% of the 128 box (room for halos); the old art filled about 87%, so a
migrated container (style `plain`) draws a visibly smaller shape at the same Size. Plain, matte,
glossy and gem are drawn at the old art's fill; glowing and neon keep the smaller core with the halo
around it. Regenerate the tiles; the art tests follow (the border-transparency check still holds).

### M10. Review

As M5 and M6, over M7-M9's diff.
