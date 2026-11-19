# Data flow — Ka0s Range Master

The core mechanic as a pipeline. The README's `## How it works` is the player-facing view of the same
pipeline; the two must not contradict each other.

## The range pipeline (plan Tasks 2 to 5)

```
consumer ─► NS.Ticker.Watch(unit)     a count per unit token; the first live unit starts the ticker
game events (target, focus, pet, mouseover, nameplate added, UNIT_FACTION): a unit change
  ─► NS.Container.UnitChanged(unit)   its instances forget the band, set, colors and chip answers
  ─► NS.Ticker.Changed(unit)          re-read now, between ticks, and sent even when the triple did
                                      not move; restarts a stopped ticker
NAME_PLATE_UNIT_REMOVED
  ─► NS.Ticker.Removed(token)         "none" at once: the token still resolves while the event runs
the ticker (one C_Timer.NewTicker, 10 Hz idle / 20 Hz in combat, stopped while no watched unit exists)
  ─► each tick: NS.Range.BeginTick()  the per-tick memo goes stale
  ─► NS.Range.Get(unit), once per unit however many consumers watch it
        no unit                        → "none"
        pcall(LibRangeCheck:GetRange(unit, true, nil, 0)); raised or secret → "unknown"
                                       (maxCacheAge 0: the library's own 0.1 s cache, keyed by
                                       token when the GUID is a secret, is never read)
        no answer, on WoW Forever      → the Compat ladder walk (spell rungs only on a friendly
                                         unit in combat; a spell rung only while it is usable)
        still no answer                → "unknown"
        otherwise                      → "known", minYd, maxYd (maxYd nil: open-ended)
  ─► RANGE_UPDATED (unit, state, minYd, maxYd)   sent only when the triple moved (or on Changed)
  ─► else NS.Ticker.OnSteady(unit)    the renderer: an instance with spell chips asks each again and
                                      renders only when an answer moved (an edge inside a bracket)
  ─► modules/Container.lua: the instances watching that unit, and no other (bucket container.render)
        NS.Range.InSpellRange per spell chip → inst:Render(state, minYd, maxYd, spellResults)
        the anchor's say, then NS.Visibility.Evaluate → shown, alpha (hidden: stop here)
        NS.BandSets.ForUnit (the friendly override) → NS.BandSets.Resolve → band index
        band or set changed → recolor the border, the fill and every element (else nothing)
        text changed        → SetText (else nothing); a cell's width moved → re-layout
        sounds on           → NS.Sounds.OnBand(inst, band, GetTime()) (also on each steady read)
the combat edge, a General visibility or Master opacity write ─► NS.Container.RefreshVisibility
SPELLS_CHANGED ─► NS.Range.Rebuild()  0.5 s after the last one: the known-spell cache again, the ladder dropped (rebuilt on the next Forever walk)
```

Every container instance watches its unit through `NS.Ticker.Watch` when it is acquired and
`Unwatch`es it when it goes back to the pool, so the ticker runs exactly while a drawn container has
a live unit. A `nameplates` container watches through its per-plate instances, one per eligible plate
token, each watched from `NAME_PLATE_UNIT_ADDED` (`NS.Plates.Added`) until `_REMOVED` parks it.

## The preview modes (plan Task 7)

```
NS.SetTestMode / NS.SetSimMode (the one writer each) ─► MODE_CHANGED (mode, on, why)
  ─► modules/Sim.lua: Sim on ─► LibKa0s-Sim session "sweep" Start + Run; off ─► Stop(reason)
  ─► modules/Preview.lua: NS.Preview.Refresh ─► Kind(): "sim" (a session runs) / "test" / nil
        NS.Range.SetSource(the sweep's or the 20–25 placeholder, or nil)   a new tick
        NS.Container.SetPreview(kind)   stand-ins for nameplates containers, strips, every
                                        instance redrawn from the source, sound state forgotten
        NS.Ticker.Refresh()             the live ticker carries the fake range from here
sweep step (1 s) ─► the distance ─► NS.Ticker.Refresh ─► RANGE_UPDATED ─► the render above
session ends (last step, stop, combat, stand-down) ─► OnStop ─► Refresh ─► NS.SetSimMode(false)
```

## Placement (plan Task 6)

```
CONTAINERS_CHANGED ─► NS.Container.Sync ─► inst:Apply ─► NS.Anchors.Apply(inst, c)
     screen     stored point on UIParent; unlocked: drag strip ─► drag stop ─► NS.CM.SetPosition
     frame      NS.FrameProviders.Resolve ─► found: SetPoint on it (held in combat → PLAYER_REGEN_ENABLED)
                                          └► missing: hidden, one debug line ─► ADDON_LOADED /
                                             PLAYER_ENTERING_WORLD ─► Retry
     nameplate  NS.Plates.Get(unit) ─► on the plate, or hidden; re-placed on the unit change and plates
     plates     (nameplates container) NS.Plates.SyncAll ─► one instance per hostile plate (all with
                includeFriendly)
     cursor     one shared OnUpdate while a cursor container is shown ─► GetCursorPosition / scale
NAME_PLATE_UNIT_ADDED ─► NS.Plates.Added ─► track (forbidden: nil) ─► instances built, own plates placed
                      └► next frame: the same again (a plate populated late)
NAME_PLATE_UNIT_REMOVED ─► NS.Plates.Removed ─► instances parked; own-plate container on that plate
                           frame hidden ─► next frame: placed again ─► NS.Ticker.Removed
```

## Container writes (plan Task 4)

```
NS.CM.Create / Delete / Duplicate / Rename / CopySettings / RestoreSnapshot, NS.Presets.Apply / Undo
  ─► the registry written at once
  ─► NS.CM.RequestApply()             one zero-delay C_Timer per frame, however many writes
  ─► next frame: FlushPending         in combat: held (one debug line) until PLAYER_REGEN_ENABLED
  ─► CONTAINERS_CHANGED               once; the renderer
  ─► NS.Container.Sync()              an instance for every enabled container (Acquire: the pooled
                                      frame, its settings applied, its unit watched), back to the
                                      pool for a deleted or disabled one
BANDSETS_CHANGED ─► NS.Container.Repaint()   every instance repaints from its last triple
the skin's OnLooksChanged ─► NS.CM.RequestApply()   the HUD face follows the skin, next frame,
                                                    held through combat like every apply
```

A stood-down addon arms no timer; the stand-up asks for one apply.

## Startup and the latch (plan Task 1)

```
login ─► OnInitialize: InitDB → RunMigrations → ApplySkinChoice → slash → launcher
      ─► OnEnable: SyncEnabledHold (the latch, from the stored `enabled`)
                   ─► if up: RegisterLifecycleEvents
                   ─► NS.CM.RequestApply (the first draw of the stored containers, next frame;
                      stood down, it is owed to the stand-up), whatever the skin did
                   ─► CreateOptionsPanel (eager category) ─► MaybeShowSkinPicker
```

- **Settings.** Every write, from the panel or `/rm set`, goes through `NS.SetByPath`: validate,
  store, one `[Set]` debug line, the row's `onChange`. `enabled`'s onChange moves the latch.
- **The latch.** `core/LifecycleSetup.lua` holds two named holds, `disabled` (the stored switch) and
  `perf` (a capture's suspended arm). The first hold taken runs `StandDown` (both modes end, the skin
  picker goes down, the lifecycle events unregister, the range ticker and the pending spell rebuild
  are canceled, and every tracked bus subscription unregisters); the last released runs `StandUp`,
  which re-registers from the settings as they are then and re-reads every watched unit.
- **The preview modes.** `NS.SetTestMode` and `NS.SetSimMode` are the one writer of each. A start is
  refused in combat and while stood down; a change sends `MODE_CHANGED (mode, on)` and refreshes an
  open panel. `PLAYER_REGEN_DISABLED` ends both (`addon:OnCombatChanged`, bracketed `combatEdge`).
- **Profiles.** A switch, copy or reset is traced once, the skin picker goes down unmarked, the new
  profile is migrated and backfilled, its skin applied, the latch re-read, and the panel refreshed.

## Components

The hub's components table (`docs/ARCHITECTURE.md`, Overview), one at a time: what each holds,
its seams and the edge cases it is built for.

### The range engine

`NS.Range.Get(unit)` answers `state, minYd, maxYd`: `"none"` (no such unit), `"unknown"` (it exists
and nothing could bound it: no answer, a raise, a secret) or `"known"` (`minYd` a number, `maxYd` a
number or nil for open-ended). It is memoized per tick and keyed by unit token, never by GUID (a GUID
can be secret on 12.x), so N containers on one unit cost one query per tick. On WoW Forever, when
LibRangeCheck answers nothing for a unit that exists, the Compat ladder is walked instead
(`NS.Compat.RangeLadder()`: items at the three reliable yards 20/30/35, the duel and follow interact
distances race-adjusted, known seed spells); in combat on a unit the player cannot attack it asks the
spell rungs only, because the client refuses item and interact checks there. `NS.Range.InSpellRange`
asks `C_Spell.IsSpellInRange` only for a spell the player knows.

`NS.Ticker` holds the watch list (a count per unit token) and the one `C_Timer.NewTicker`: 10 Hz out of
combat, 20 Hz in combat (re-armed on the combat edge), stopped while no watched unit exists and
restarted by the event that brings one back. Each tick reads every watched unit once and sends
`RANGE_UPDATED` only for a unit whose triple changed; mouseover, which has no "cleared" event, is
re-read through `UnitExists` every tick. `NS.Ticker.Changed(unit)` is the unit-change read: a
different unit now sits behind the token, so the triple is sent even when it did not move. A read
whose triple did not move reaches the `NS.Ticker.OnSteady` listeners instead (the renderer re-asks
its spell chips there). The stand-down cancels the ticker and the debounced spell
rebuild; the stand-up re-reads and re-announces every watched unit. Pipeline: `docs/data-flow.md`.

### Band sets

A band set is a named, ordered list of yard bands shared by every container that picks it
(`modules/BandSets.lua`, `NS.BandSets`). `Resolve(setId, state, minYd, maxYd)` turns a range triple
into a band index: `"none"` answers nil, `"unknown"` answers `"unknown"` (the set's own label and
gray), `"known"` picks by the far bound (`matchBy = "max"`, a band holds `(from, to]`, an open-ended
bracket reads as infinitely far) or the near one (`"min"`, `[from, to)`). Every stored set is
normalized on each write and on load (sorted, contiguous from 0, last band open-ended, no zero-width
band, at least one band), so `Resolve` is total over [0, infinity). `ForUnit(container, unit)` picks
the container's `bandSetFriendly` when it is set, exists and `NS.Compat.IsFriend` says the unit is
friendly, else its `bandSet`, else the default. The default set is the first in `bandSetOrder`; the
first-run seed puts the class default there (`NS.BandSetPresets.DefaultFor`). Deleting a set moves
every container on it to the named replacement or the default (a friendly override on it falls away
unless a replacement was named), and the last set cannot be deleted. Names stay unique, case-blind:
`Create`, `Duplicate` (`"<name> copy"`) and `Rename` all go through `UniqueName` (`Caster 40 copy`,
`Caster 40 copy 2`), as containers do, so `/rm bands <name>` names one set. The Hunter preset is two lists,
one per client, picked once at load (clients-§5): WoW Forever's has the 5-8 yd Auto Shot dead zone.

### Containers and presets

`NS.CM` (`modules/ContainerManager.lua`) is the container registry's one runtime writer: `Create(unit?,
opts?)` (a deep copy of the template on the default band set, the class's spell-chip seeds from
`defaults/SpellSeeds.lua`, `opts` merged over it but never over the checked positional unit, a
screen container staggered by id), `Delete`,
`Duplicate` (after its source, `"<name> copy"`, a screen copy offset), `Rename`, `UniqueName`
(`Target`, `Target 2`, case-insensitive), `SetField` (one dotted field; `elements.order` only as an
arrangement of the four elements, `IsElementOrder`), `CopySettings` (never name, enabled, unit or anchor, nor the caption's own `label.text`),
`Clear`, and `Snapshot` / `RestoreSnapshot`, which carry both registries, ids included, the band-set
half through `NS.BandSets.Snapshot` / `RestoreSnapshot`. A restore never rewinds either id counter
(each keeps the higher of its own and the snapshot's), so an id is never reused. Every write calls `RequestApply`, which
arms one zero-delay `C_Timer`: a whole preset announces `CONTAINERS_CHANGED` once, on the next frame.
A flush under combat lockdown is held (one debug line) and runs on `PLAYER_REGEN_ENABLED`; a stood-down
addon arms no timer, and the stand-up asks for one apply. A profile switch, copy or reset (the
three AceDB callbacks, `adoptProfile` in `core/RangeMaster.lua`) replaces the registry whole, so it
asks for one apply too.

`NS.Presets.Apply(key)` (`simple`, `text`, `numbers`, `advanced`, `expert`) snapshots, clears and creates through
`NS.CM`, and answers the snapshot; `Undo` restores it (one level). The Undo slot belongs to the
profile it was taken on: `adoptProfile` calls `ForgetUndo` on a switch, copy or reset. Every preset puts target, focus, pet and
mouseover free on screen at their homes (`Presets.HOME`), on the template's frame (background on, the
band-colored border at 25%) and matte dot; only the elements differ. Simple: the dot. Intermediate
(Range Text, `text`): the band's text label. Intermediate (Range Numbers, `numbers`): the range
number. Advanced: dot + number + text. Expert: Advanced with spell chips, the Healer set as the
friendly override on target, focus and mouseover (reused by name, else created), sounds on target
(its set's out-of-range band gets `NS.Presets.OOR_SOUND` through `NS.BandSets.SetBandSound` when it
has no sound), plus target on its own nameplate (diamond + number) and every hostile nameplate (dot +
the `max` number), both in combat only. `Describe(key)` feeds the
preset cards on General › Presets. `PickerDue` / `MarkPickerSeen` are the one runtime reader and
writer of `profile.seeded`, the first-run preset picker's sentinel (`settings/Presets.lua` shows the
picker and marks it seen as it shows). The picker's picks preview through `BeginPreview` /
`EndPreview(keep)`: one snapshot of the player's set at the first pick (a later pick restores it
before it builds, so what one preview added to the band sets never outlives it), restored on Not now, combat,
the take-down and AceDB's shutdowns, or made the Undo slot when Apply keeps it. Its own take-down
(`NS.HidePresetPicker`: the stand-down, every profile event, the shutdowns) closes it quietly and
offers no skin picker; the player's close does, and a profile event asks for both prompts afresh, the skin picker still behind.

### Rendering

`NS.Container` (`modules/Container.lua`) keeps one instance per enabled container, from a
LibKa0s-Pool-1.0 keyed pool (`core/PoolSetup.lua`) keyed by container id. `CONTAINERS_CHANGED` runs
`Sync`: `Acquire(id)` for every enabled container (the pooled frame, its settings applied, its unit
watched through `NS.Ticker.Watch`) and back to the pool for a deleted or disabled one; a release
parks the one object, drops its watch and forgets what it drew. `BANDSETS_CHANGED` repaints every
instance from its last triple, and the skin's `OnLooksChanged` asks for an apply
(`NS.CM.RequestApply`, the next frame and held through combat) so the HUD face follows the skin.
`RANGE_UPDATED` reaches the instances watching that unit and no other (bucket `container.render`);
each asks its spell chips' answers (`NS.Range.InSpellRange`) and renders. A unit change (a retarget,
a new focus, mouseover or pet, a plate token handed to a new plate, `UNIT_FACTION`) runs
`NS.Container.UnitChanged`, which makes the instances on that token forget what they drew, then
`NS.Ticker.Changed`, so the band set is resolved again for the new unit's reaction, the class color
is the new unit's and every chip is asked again, whatever the bracket did. On a read whose triple did
not move (`NS.Ticker.OnSteady`) an instance with chips asks each again and renders only when an
answer moved, because a spell's range edge can fall inside one LibRangeCheck bracket.

A render resolves the band (`NS.BandSets.ForUnit`, then `Resolve`) and recolors the border, the fill
and every element only when the band index or the set changed; an element sets its text only when
the string changed, and the layout runs on an apply or when a cell's width moved. An unknown range
draws the set's unknown label (`?`) in its gray, never a band; no unit hides a container that hides
with no unit. Colors read `band` (the band's frame, text or indicator color), `fixed` (the swatch) or
`class` (the TRACKED unit's class color, the swatch's alpha kept, an unresolvable class falling
through to the swatch; options-ui-§17, because a range container describes its unit; the
color rows declare `classColorSource = "unit"`). The elements follow
`elements.order` along `layout.direction`, `spacing` apart, centered across; only an enabled element
is ever built, and one turned off is hidden. The caption (`label`, while enabled; no element of the
order) sits between the padding and the elements' block on its side (top, bottom, left or right),
`gap` px from it (no gap with no element shown), and the cells are offset by it: the block and the
caption are centered on each other, and the root grows to hold both (a fixed-size box keeps its size,
the caption inside it). Paint colors the caption with the frame and measures it again, so a width
that moved lays the container out again. The number writes the bracket in one
of six formats and `40+` for an open-ended one, never an invented far bound. The indicator draws
this addon's shape art in the stored style (`media/textures/indicators/<shape>_<style>`, matte by
default), LibKa0s-Widgets' data bar (fuller the nearer
the band, empty when unknown) or a spell icon. The spell chips are an array pool per element, each
chip colored by its own answer and repainted only when that answer moves. Placement is
`NS.Anchors.Apply` (below). A `nameplates` container has no single instance: it owns one per eligible
plate, from a second keyed pool (`AcquirePlate`, `ReleasePlate`, `GetPlate`, `ForEachPlate`), each
watching its plate token; which plates get one is the plate registry's call. Frames stack by
`NS.Constants.LAYERS` (the HUD strata; fill, border and overlay offset over the root). Each instance
takes its own root level when built (`BASE + slot * STRIDE` over UIParent, the slot cycling 1..`SLOTS`),
so overlapping displays stack whole rather than band by band (frame-layering-§3). The root's strata is
the container's Frame strata only when the row offers it (`NS.ContainerValues.STRATA`), else HUD.

### Anchors

`NS.Anchors.Apply(inst, container)` (`modules/Anchors.lua`) picks the mode and hands the instance to
that mode's file, detaching the old one first; a mode may hide the instance while what it belongs on
is missing (`inst:SetAnchorHidden`), and the renderer tells the anchors each show and hide
(`ShownChanged`). The five modes:

- **screen** (`modules/Anchors_Screen.lua`): the stored point on `UIParent`. While `locked` is false
  each screen container wears LibKa0s-Widgets' drag strip (`RefreshLock`, from the Master controls'
  `locked` row); a drag ends in `NS.CM.SetPosition`, the registry's own writer, rounded to whole
  pixels, and cannot start in combat. `NS.ResetPositions` (`/rm resetposition`, the Reset position
  button) puts every screen container back at the new-container point (`NS.CM.ResetPosition`).
- **frame** (`modules/Anchors_Frame.lua`): on a unit frame from `NS.FrameProviders`
  (`modules/FrameProviders.lua`): `blizzard` (TargetFrame, FocusFrame, PetFrame), `ellesmere`
  (EllesmereUIUnitFrames_Target, _Focus, _Pet, read as globals, never `EllesmereUIDB`) or `custom` (a
  global frame name, typed or picked), at the container's own `anchor.frame` point (above the frame by
  default), never its screen point, so a drag or a new container's screen stagger never carries onto
  the unit frame. A missing frame hides the container at its screen point with
  one debug line, and is looked for again on `ADDON_LOADED` and `PLAYER_ENTERING_WORLD`. No anchor
  write onto a unit frame happens in combat: it is held and runs on `PLAYER_REGEN_ENABLED`
  (`FlushDeferred`). Mouseover has no frame from either addon, so a mouseover container with no custom
  frame follows the cursor instead.
- **nameplate** (`modules/Anchors_Nameplate.lua`): on the unit's own plate
  (`NS.Plates.Get(unit)`), at the container's `nameplate` point, re-placed on a unit change and on a
  plate coming or going; pet has no plate in practice, so it is hidden.
- **plates**: a `nameplates` container's per-plate instance, on its plate. `NS.Plates` tracks every
  plate token from `NAME_PLATE_UNIT_ADDED` / `_REMOVED`; a plate is hostile through
  `NS.Compat.CanAttack`, and a container with `nameplate.includeFriendly` takes every plate. A plate
  is identified by its frame, never through `UnitIsUnit`: a removed token's plate is compared with
  the frame an own-plate container sits on, which is hidden at once, and looked for again a frame
  later. Every `ADDED` is re-checked one frame later (WoW Forever can announce a plate before it is
  populated). A forbidden plate never comes back from `NS.Compat`'s plate reads, so it is never
  touched.
- **cursor** (`modules/Anchors_Cursor.lua`): one shared driver frame, its `OnUpdate` armed only while
  a cursor container is shown, places each at `GetCursorPosition()` over `UIParent`'s effective
  scale plus the container's own `anchor.cursor` offset (below and right of the cursor by default,
  never the screen point) (bucket `cursor.follow`).
- **mockplate** (`modules/Anchors_Mockplate.lua`), unlocked out of combat only: an own-plate
  container and a `nameplates` container's stand-in sit at their screen point (and drag, as a screen
  container does) beside a stand-in nameplate, a child of the root hung off it by the inverse of
  the container's `nameplate` point and offsets, so the pair reads as the container will sit on a
  real plate. A write to those rows re-places it at once. The drag strip is lifted over the stand-in
  (`NS.Anchors.Screen.SetLift`), worked out from the stored points and the laid-out size alone.
  Locking or combat puts the container back on `nameplate` (or its per-plate instances).

`NS.FramePicker.Start(onPick)` (`modules/FramePicker.lua`) is the custom provider's pick on screen: an
overlay outlines the nearest named ancestor of the frame under the cursor; Enter picks it and Escape
cancels. The overlay takes no mouse, so a click would reach the frame under it; the pick reads the
keyboard only (frame-layering-§4 retired the full-screen click catcher). It is refused in combat and the combat edge cancels one in progress.
`/rm pick` and the Containers page's **Pick on screen** button call it through
`NS.PickFrameForSelected` (`settings/Containers.lua`): a pick sets the selected container to the
`frame` mode, the `custom` provider and the picked frame's name, through `NS.CM.SetField`.

### Behavior and modes

- **Visibility** (`modules/Visibility.lua`): `NS.Visibility.Evaluate(container, unit, state?)` answers
  `shown, alpha`. The Master controls' General visibility (always, inCombat, outOfCombat, never) wraps
  the container's `visibility.combat` (any, in, out); with no unit `hideNoUnit` decides; with one,
  `visibility.reaction` (any, hostile, friendly) through `NS.Compat.CanAttack` / `IsFriend`, an
  unreadable reaction passing neither. The opacity is Master opacity times `oocAlpha` out of combat,
  times the layout's own. The renderer asks on every render (the anchor's say first), and again over
  every instance on the combat edge (`NS.Visibility.SetCombat`, then
  `NS.Container.RefreshVisibility`, from `OnCombatChanged`) and on a write of the General visibility
  or Master opacity rows; a unit or reaction change re-renders through the ticker. Master scale
  multiplies each container's scale on its next apply (`NS.CM.RequestApply`, held through combat).
- **Band sounds** (`modules/Sounds.lua`): the renderer reports each shown instance's band on every
  render and every steady read (`NS.Ticker.OnSteady`) to `NS.Sounds.OnBand(inst, band, now)`. State
  lives on the render instance (`inst.sound`): a band plays its LibSharedMedia sound once it has held
  0.2 s, not within 1 s of the container's last sound, never for the first band after the unit
  changed (`NS.Container.UnitChanged`, or the unit going away), and a flicker back into the band that
  had settled is quiet. `NS.Sounds.Reset` (a unit change, a faction change, a preview starting or
  ending) forgets the bands but keeps the last sound's time, so the 1 s gap is the container's and
  survives a retarget. A `nameplates` container never sounds: its per-plate instances keep no state,
  and its Test or Sim mode stand-in is turned down by `NS.Sounds.Wants`. The Expert preset's out-of-range key is built in (`NS.Sounds.BUILTIN`: the raid warning
  chime, file id 567397) and registered with LibSharedMedia at load.
- **Test mode** (`modules/Preview.lua`): `NS.Preview.Refresh` is the one caller of
  `NS.Range.SetSource` (a fake range every read answers, for any token) and
  `NS.Container.SetPreview`. Test mode's source is the `20–25` placeholder (every spell chip in range).
  While a preview runs every enabled container shows, whatever its visibility says: one whose frame
  or plate is missing at its screen point, and a `nameplates` container through a stand-in instance
  in the main pool that goes with the preview. Each wears LibKa0s-Widgets' TestStrip (`dock =
  "hud"`, amber `TEST`, cyan `SIM`), including an instance acquired while the preview runs (a
  container created or enabled, a plate added, a pooled frame coming back). The strip stacks beyond
  the screen anchor's drag handle: one built before the first unlock is docked again when the handle
  is built (`inst:DockStrips`). Its dock target is the root, a root on a nameplate included: the
  library's dock answers a refused measurement as "no flip" (LibKa0s v1.106.0; ARCHITECTURE.md,
  *Taint Notes*). While a display's drag
  strip shows, its label ends in the TEST or SIM tag and the TestStrip is hidden: the tagged drag
  strip is that display's marker (preview-mode, *Where the strip sits*, v2.114.0;
  `NS.Anchors.Screen.Tagged`), and the TestStrip returns when the drag strip hides. The ticker, the memo, `RANGE_UPDATED` and the render are the live
  ones.
- **Sim mode** (`modules/Sim.lua`): a LibKa0s-Sim-1.0 session on an empty seam (it simulates no
  client read), one scenario `sweep`: 0, 5, … 50, … 0 yd, one step a second, then the step that ends
  it. The range is the bracket a yard either side (`50+` at the far end); a chip is in range while the
  distance is inside the spell's own range. The step panel shows for the whole session and is pinned
  while it runs: no window strip marks this addon's session, so its close mark is hidden and it comes
  off `UISpecialFrames` (the vendored library takes no `close = false` on its panel descriptor, so
  the pin is composed on the frame, `RangeMasterSimPanel`); the stop puts both back. Sim mode on
  starts and runs the session; the session ending (its last step, `/rm sim stop`, the panel, combat,
  a stand-down, Sim mode off) turns the mode off and the live range back on; a typed `/rm sim start
  sweep` turns the mode on. A running sweep wins over Test mode, and Test mode is refused while one
  runs. The library's lines go to the debug console; a typed `/rm sim <verb>` answers in chat.
- **Both modes** keep one writer each (`NS.SetTestMode`, `NS.SetSimMode`, `core/RangeMaster.lua`; the
  plan's `NS.Preview.SetTestMode` and `NS.Sim.SetSimMode` call them), are refused in combat and while
  stood down, and end on `PLAYER_REGEN_DISABLED` and at the stand-down (the sweep stops with reason
  `combat` or `standDown`). Nothing either draws is stored.
- **Lock**: the Master controls' Lock frame row, `/rm lock` / `/rm unlock` and the launcher's Locked
  entry show LibKa0s-Widgets' drag strip on every screen container while unlocked (Anchors, above),
  and, out of combat, every container shows as in a preview (`NS.Container.RefreshLock`): no
  visibility rule asked, a missing frame or plate at its screen point, a `nameplates` stand-in, and a
  container whose unit is absent drawing `NS.Preview.PLACEHOLDER` with its state kept "none" and no
  band sound. Every container instance but a per-plate one wears the drag strip then
  (`NS.Anchors.Screen.Track`), and a cursor or own-plate container is placed on the screen anchor at
  its stored point (`NS.Anchors.Refresh`, modules/Anchors.lua's mode choice), so it holds still and
  drags; a unit-frame one stays on its frame and does not drag. The combat edge ends it and the leave
  edge brings it back.
