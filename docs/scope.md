# Scope — Ka0s Range Master

## What it does

Range Master shows how far away a unit is, as the narrowest bracket the game's range checks allow,
on displays the player builds. Each display (a **container**) watches one unit: `target`, `focus`,
`pet`, `mouseover`, or every enemy nameplate at once (or every one but the target's). It can show the bracket as a number, a band
label, a colored indicator and a row of the player's own spells that light when in reach, all colored
by a shared **band set**, with an optional caption naming the display. A band is a yard range or
a spell rule (the class's melee, ranged or friendly spell is in reach, the hunter's dead zone, or past
every spell band), so a band follows talents, gear and forms; its yards are the fallback. A display sits on the screen, on a unit frame (Blizzard's, EllesmereUI's or
any named frame), on a nameplate, or at the cursor. It can play a sound when the band changes, and it
can hide by combat state, reaction or a missing unit.

Six presets (Simple, Intermediate (Range Text), Intermediate (Range Numbers), Advanced, Expert, Ka0s)
build a starter set, Test mode shows placeholders for
placing and styling, and Sim mode walks a simulated target through the bands. It runs on Retail and
WoW Forever from one codebase. The full feature list is the design spec,
`docs/superpowers/specs/2026-11-18-rangemaster-design.md`, section 3.

Everything above is built in the v0.1.0 tree (plan Tasks 1 to 8) and configured from the settings
pages or `/rm`. None of it has been run in a client yet; `docs/smoke-tests.md` holds the checks that
are still owed.

## What it deliberately does not do

- **No exact distance.** The client answers "in range of spell or item X", not a number of yards, so
  the addon shows a bracket and never invents a figure between its edges.
- **No guess when the answer is hidden.** A secret value or a failed check shows *unknown* (a gray
  `?`), never "out of range".
- **No GUID tracking.** Every memo and cache is keyed by unit token, because a GUID can be secret.
- **No party, raid, arena or boss units** in v0.1.0, and no unit-frame providers beyond Blizzard,
  EllesmereUI and a custom frame name (ElvUI, Shadowed Unit Frames and Cell are deferred).
- **No import/export strings and no Edit Mode integration** in v0.1.0.
- **No reading of another addon's saved variables.** EllesmereUI's frames are found by name only;
  `EllesmereUIDB` is never read.
- **No per-display timers.** One ticker serves the whole addon, and it stops when nothing is watched.
- **No band reordering by hand.** A band set is always sorted by its edges; a band moves by changing
  where it ends, so there is no drag-to-reorder for bands.
- **No exact-distance tricks.** No map-coordinate or `UnitPosition` math and no group-only API
  (`UnitInRange`, `UnitDistanceSquared`): they answer only for party and raid members, outdoors, or
  as a secret, so the range checks are the one source.
- **No class-colored bands.** A band's own colors are fixed swatches; class color is chosen per
  container (its Color from), because it describes the tracked unit, not the band.
