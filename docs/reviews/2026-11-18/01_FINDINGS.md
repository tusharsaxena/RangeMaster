# RangeMaster v0.1.0: review findings (2026-11-18)

**Verdict: blocking issues.** There is one High finding (F-001): after a login or `/reload`, a player's
saved range displays are not drawn when their skin settings happen to match the library's defaults.
The rest are design, UX and evidence findings. No upstream or cross-addon findings.

**Resolved scope:** the whole addon on branch `feat/v0.1.0-initial-build` at `01d19d5` (the base
`master` holds only `.gitattributes`, so the branch diff is the whole tree). I reviewed the authored
source (`core/`, `defaults/`, `modules/`, `settings/`, `locales/`, the TOC) and the addon's own test
and perf code (`tests/*.lua` outside `tests/_kit/`). `libs/` and `tests/_kit/` were checked only for
vendor sync and the cross-addon pass. The spec is
`docs/superpowers/specs/2026-11-18-rangemaster-design.md`.

**Standards cross-check:** Ka0s WoW Addon Standard v2.113.0 (2026-11-16), read from the sibling
checkout `../WowAddonStandards` at `1f5767f338ce7ecd3d7a2b698baee8920eea0400`. The checkout is clean
and matches `origin/master` (`git ls-remote`). No fetched copy exists, so the `diff -rq` check did
not apply.

## Measurement run

Every run went through `~/.claude/dev-copilot/bin/ka0s-bounded`, from the repo root, with output to a
scratch path outside the repo. Nothing under the repo was written except this bundle.

| Suite | Result | Command |
|---|---|---|
| luacheck | **pass**: 0 warnings / 0 errors in 111 files | `ka0s-bounded luacheck .` |
| Headless suite (Retail profile) | **pass**: 610 passed, 0 failed, 1 skipped, 611 total | `ka0s-bounded lua5.1 tests/run.lua` |
| Headless suite (Forever profile) | **pass**: 610 passed, 0 failed, 1 skipped, 611 total | `KA0S_KIT_CLIENT=forever ka0s-bounded lua5.1 tests/run.lua` |
| Test-case inventory | **pass**: total 610, Skipped 1. The fresh `--list` output is byte-identical to the committed `docs/test-cases.md` (after CR strip) | `ka0s-bounded lua5.1 tests/run.lua --list` |
| Offline perf runner | **ran**, exit 0, all 13 scenarios, no assertion failed (figures below) | `ka0s-bounded lua5.1 tests/perf.lua` |
| Complexity (sighted, kit rev 57) | **pass**: 0 warnings, max CCN 15, 16612 NLOC / 2568 functions, avg CCN 2.1. No blind or crashed files reported | `ka0s-bounded bash tests/_kit/run-automated-tests.sh --suite complexity --no-bundle` |
| `make test` | **not applicable**: no root `Makefile` | n/a |
| Vendor sync, LibKa0s | **pass**: `libs/LibKa0s/` matches `../LibKa0s` tag `v1.105.0` `LibKa0s/` except files that exist on only one side. Those are the 214 `media/icons` files the addon does not ship (CLAUDE.md lists the 12 it does) and `media/sounds/callout` | `git -C ../LibKa0s archive v1.105.0 LibKa0s testkit \| tar -x -C <scratch>`, then `diff -rq --strip-trailing-cr <scratch>/LibKa0s libs/LibKa0s` |
| Vendor sync, test kit | **pass**: `tests/_kit/` is identical to tag `v1.105.0` `testkit/` (kit revision 57 on both sides) | `diff -rq --strip-trailing-cr <scratch>/testkit tests/_kit` |
| Cross-addon class 1 (slash tokens) | **clean**: 38 roots, no collisions, no raw `SLASH_*` registrations in loaded source. RangeMaster's roots are `rm` and `rangemaster` | the two loops in the review brief, over the 19 roster addons plus RangeMaster |
| Cross-addon class 2 (vendored minors) | **clean**: one line shared by all 20 addons. It matches the per-major minors at tag `v1.105.0`: `Bus:2 Callout:4 Charts:2 Compat:4 Core:18 DebugLog:23 Env:2 Glow:2 IconBrowser:1 Item:3 Launcher:11 Lifecycle:3 Media:13 Options:38 Perf:16 Pool:3 Role:1 Schema:3 Sim:3 Skin:18 Slash:23 Toast:4 Tooltip:1 WaypointArrow:2 Widgets:27` | the class-2 loop |
| Cross-addon class 3 (payload bytes) | **clean**: reference AbsorbTracker (175 files; RangeMaster has 174). No file differs in content. Every `diff -rq` line is an `Only in` for a per-consumer `media/icons` subset or for CombatTrail's `media/sounds/callout` | `for a in "$@"; do diff -rq AbsorbTracker/libs/LibKa0s "$a/libs/LibKa0s"; done` |
| Cross-addon class 4 (`## Interface:`) | **clean**: Retail slot `120105` everywhere (7 single-number lines and 12 two-number lines), Forever slot `16001` everywhere (12 two-number lines and 1 single-number line). RangeMaster has `120105, 16001` | the class-4 loop |
| Provenance tag | all 20 `CLAUDE.md` provenance lines read `v1.105.0`, so there is no split | the provenance loop |

Notes on the run:

- **RangeMaster is not yet in the roster.** It has no row in `WowAddonStandards/standards/ADDONS.md`
  (design spec 5.8 drafts one), so `scripts/roster_clients.py RangeMaster` could not resolve a
  Clients value. I ran both kit profiles because the TOC carries two numbers, and I added RangeMaster
  to the 19-addon roster list by hand for the cross-addon pass. The missing row is an audit and
  roster matter, so it is recorded here and not raised as a finding.
- **Committed artifacts compared with today's run.** `docs/test-cases.md` matches the fresh inventory.
  The README badge reads `610/610`, which is correct: the one skip is left out of both figures, as
  testing-§5 requires. The newest bundle (`docs/automated-tests/20261118-091529`, measured at `87a5620`,
  2 commits behind HEAD) has the same complexity figures (16612 / 2568 / max 15) and the same perf
  byte figures as today's run. The two later commits touch docs only. `docs/performance.md` states no
  figures, so it cannot drift. `docs/perf-analysis/` holds only its `README.md`, so there are no
  in-client captures to cite.
- **Today's offline perf figures** (bytes per iteration; timings are for orientation only):
  combatEdge 0.0, settingsRead 0.0, range.get 0.0, range.get.hit 0.0, ticker.tick 16.9,
  ticker.tick.moving 16.4, render.quiet 36.8, container.render 3357.4, render.plates.quiet 7.4,
  render.plates 6714.0, cursor.follow 0.0, probeOverheadOff 0.0, probeOverheadOn 0.3.
- **Scratch experiments.** I wrote four throwaway Lua scripts under the session scratchpad. Each
  loads the addon through the vendored kit loader exactly as `tests/run.lua` does. They back F-001
  and the validation checks noted at the end of this file. None was written into the repo, and
  `git status --short` was empty afterward.

## High

### F-001: Saved displays are not drawn at login unless a skin setting differs from the library default `[correctness]`

- **Where:** `core/RangeMaster.lua:44-55` (`addon:OnEnable` asks for no container apply).
  `modules/Container.lua:712` `NS.Skin.OnLooksChanged(function() NS.CM.RequestApply() end)` is the
  only route to the first apply. It fires only when `core/SkinSetup.lua:497-507` `NS.ApplySkinChoice`
  changes something. Each library setter returns early when nothing changed:
  `libs/LibKa0s/Skin.lua:552` `if source == o.source and skin == o.skin then return false, false end`
  and `:586` `if panel == (o.ignorePanel == true) and fonts == (o.ignoreFonts == true) then return false, false end`.
  Today the first apply happens only because `defaults/Profile.lua:35` ships `ignorePanel = true`, and
  the owner was registered with it unset.
- **Problem:** Nothing in the login path asks ContainerManager to apply the stored containers. The
  first `CONTAINERS_CHANGED` comes from a side effect: the skin's "looks changed" callback.
- **Impact:** A player on the client-default skin who has unticked *Ignore settings panel* (General >
  Skin) sees **no range displays after any login or `/reload`**. They stay hidden until something
  writes a container, Master scale or the profile. The ticker never starts and no range is shown.
- **Reachability:** Any player on the default skin who has unticked *Ignore settings panel* (a
  shipped, documented checkbox), on every login and reload. More generally, any future change that
  makes the profile's skin defaults equal the library's registration defaults breaks the first draw
  for everyone.
- **Measurement:** This is a scratch reproduction, not a suite case. I loaded the addon with the
  real kit loader, stored one container, set the stored `skin.ignorePanel = false`, then ran
  `OnInitialize`, `OnEnable` and `mocks.__fireTimers()`. `NS.Container.Get(1)` was `nil`. With the
  default `true` it was an instance. After login, `NS.CM.__pending()` is `false` with no timer armed,
  against `true` with a timer armed by default.
- **The suite missed it:** No case in today's 610-case inventory loads a profile that already holds a
  container and checks it is drawn after `OnInitialize` and `OnEnable`. The suite only ever boots with
  the default `ignorePanel = true`, so the hidden dependency is always met.
- **Fix direction:** Have `OnEnable` ask for one apply through the registry's own writer
  (`NS.CM.RequestApply()`), the same call `CM.StandUp` makes, so the first draw no longer depends on
  the skin's callback (architecture-§5; slash-commands-§7 "rebuild from the current settings").

## Medium

### F-002: A frame pick clicks the frame under the cursor `[ux]`

- **Where:** `modules/FramePicker.lua:143` `overlay:EnableMouse(false)`, and `:119-121`, which reads
  the click by polling `IsMouseButtonDown` and fires `picked(name)` on the press.
  `core/Compat.lua:254` `return foci[1]` answers only the topmost focus.
- **Problem:** The pick overlay takes no mouse input, so the left-click that picks and the right-click
  that cancels both go to the frame underneath.
- **Impact:** Picking `PlayerFrame` targets yourself. Picking an action button casts its spell.
  Right-click to cancel over a unit frame opens its context menu. Picking a minimap button runs it.
  The pick works, but the click also does whatever that frame normally does.
- **Reachability:** Any player who uses *Pick on screen* (Containers > General > On the unit frame) or
  `/rm pick`, on every pick.
- **Fix direction:** Keep the mouse pass-through (a full-screen click catcher is what
  frame-layering-§4 retired) and confirm the pick from the keyboard the overlay already owns: Enter
  picks the outlined frame and Escape cancels. Mouse buttons then do nothing to the picker. The
  overlay label and the `/rm pick` help text change with it.

### F-003: Overlapping displays interleave their layers `[layering]`

- **Where:** `modules/Container.lua:133-135`: every root is
  `CreateFrame("Frame", nil, UIParent)` at `LAYERS.STRATA.HUD` with the implicit level.
  `modules/Style.lua:196-198` `child:SetFrameLevel(levelOf(root) + offset)` with the fixed offsets in
  `core/Constants.lua:91-96` (FILL 1, BORDER 2, OVERLAY 4).
- **Problem:** All container roots get the same strata and level, so the fill, border and overlay of
  two displays sit on the same levels. Where two displays overlap, their layers interleave in no fixed
  order. frame-layering-§3 *Peers stack whole* requires a defined order between overlapping peers.
- **Impact:** One display's fill or border can draw over another's number or text. This happens with
  `nameplates` per-plate instances in a dense pack, where plates overlap all the time, and when a
  cursor or mouseover display passes over a screen display.
- **Reachability:** Any player with an *All nameplates* container (the Advanced preset makes one)
  fighting a pack of overlapping plates, or with a cursor display. Both are default preset layouts.
- **Fix direction:** Give each instance a deterministic base level with a stride of at least the
  display's band height (frame-layering-§3, with the band named in `NS.Constants.LAYERS` per
  frame-layering-§5), set it when the instance is built, and set it again after any re-level.

### F-004: Spell chips are seeded for one class, but the default profile is shared across characters `[design]` `[ux]`

- **Where:** `modules/ContainerManager.lua:178-182` `seedSpells()`, called once at create
  (`:213` `c.elements.spells.list = seedSpells()`). `core/Database.lua:163`
  `AceDB:New("RangeMasterDB", NS.defaults, true)` makes the shared `Default` profile the default.
  `docs/ARCHITECTURE.md:220-223` records that the list has no settings row.
- **Problem:** The chip list is fixed to the class of the character that created the container.
  Every character on the default profile shares it, and no surface can edit it.
- **Impact:** An alt of a different class sees the first character's spells as chips. Those spells are
  unknown to the alt, so `NS.Range.InSpellRange` answers `nil` and the chips stay gray. The only way
  out is to delete and recreate the container, or switch to a per-character profile. The known
  limitation records that the list cannot be edited, but not this effect.
- **Reachability:** Any player with two characters of different classes on the default `Default`
  profile who turns spell chips on. The Advanced preset turns them on for Focus.
- **Fix direction:** Either resolve the chip list per class at read time (store an explicit list
  only when the player edits one, and fall back to the current character's seeds otherwise), or add
  the list editor (an `O.IdList`-style row, options-ui). Re-seeding on login would quietly overwrite
  a stored choice, so do not do that.

### F-005: The zero-overhead perf scenario checks the wrong comparison on the wrong path `[tests]` `[perf]`

- **Where:** `tests/perf.lua:240-252`: `probeOverheadOff` and `probeOverheadOn` both run
  `NS.addon:OnCombatChanged("PLAYER_REGEN_ENABLED")`, and the assertion is
  `probeOff.bytesPerIter <= probeOn.bytesPerIter + 1`.
- **Problem:** performance-§9 requires the hottest bracketed path, run with capture off, to be pinned
  against the same path with instrumentation absent. This scenario compares dormant against armed on
  the combat edge, which is not a hot path. It is trivially true: an armed bracket always allocates at
  least as much.
- **Impact:** "A dormant bracket is free" (performance-§2) is not shown for `ticker.tick` or
  `container.render`, which run 10 to 20 times a second. A bracket that allocated or called
  `debugprofilestop` while capture was off would still pass.
- **Reachability:** Evidence only. The shipped brackets read `Perf.on` correctly
  (`modules/Ticker.lua:107`, `modules/Container.lua:677`), but the claim is unverified. Capped at
  Medium.
- **Fix direction:** Add a dormant arm over the moving tick (`ticker.tick.moving` and
  `container.render` with `NS.Perf.on = false`). Count `debugprofilestop` and `Perf.Note` calls, which
  is a deterministic quantity, and assert zero, with a `-- red under:` note naming an unconditional
  bracket. Keep the byte figure beside it.

### F-006: A band-set delete writes container fields behind the container registry's back `[design]`

- **Where:** `modules/BandSets.lua:387-394` `reassign(...)`: `if c.bandSet == id then c.bandSet = target end`,
  called from `BandSets.Delete` (`:398-409`). Compare `modules/ContainerManager.lua:2-4`: "the ONE
  runtime writer of profile.containers ... (architecture-§5; the other writer is core/Database.lua's
  load pass)".
- **Problem:** The band-set registry writes a member field of the container registry directly.
  That makes a third writer of `profile.containers` that the ContainerManager contract does not name.
- **Impact:** No `CONTAINERS_CHANGED` is sent and no field-write seam runs. The renderer only
  catches up because `BANDSETS_CHANGED` repaints. Any later reaction tied to the container field
  (a settings refresh, validation, a trace) is skipped. architecture-§5 requires one runtime writer
  per registry and row-addressed member fields to go through the seam.
- **Reachability:** Any player who deletes a band set that a container uses (Band sets page >
  Delete). It works today, so this is convention drift.
- **Fix direction:** Have `BandSets.Delete` reassign through `NS.CM.SetField(id, "bandSet", target)`
  and `SetField(id, "bandSetFriendly", ...)`, the registry's field writer. The band-set registry then
  owns only band sets.

## Low

### F-007: Two user-facing chat lines are not localized `[locale]`

- **Where:** `core/SkinSetup.lua:467`
  `local RELOAD_LINE = "Reload your interface (/reload) to finish changing the skin."` (printed at
  `:473` and `:501`), and `settings/Schema.lua:315`
  `d.print("LibKa0s-Schema-1.0 is missing, so the schema was not checked")` (degraded stub).
- **Problem:** Both lines are printed to chat as hard-coded English instead of `L[...]` keys.
- **Impact:** A future locale cannot translate them. Every other line in the addon goes through `NS.L`.
- **Reachability:** A player whose profile change or `/rm set skin.source` leaves an EllesmereUI skin
  that painted this session (the first line). An install missing LibKa0s (the second).
- **Fix direction:** Move both strings into `locales/enUS.lua` and read them through `NS.L`
  (localization-§1, §3).

### F-008: `/rm delete` deletes at once while the panel asks first `[ux]`

- **Where:** `settings/Slash.lua:268-274` `printf(L["Deleted container '%s'."], NS.DeleteContainer(id))`,
  against `settings/Containers.lua:327-332`, which shows `RANGEMASTER_DELETE_CONTAINER` first.
- **Problem:** The two surfaces for one destructive action behave differently. The slash verb has no
  confirmation and no undo.
- **Impact:** A typo such as `/rm delete 1` instead of `/rm select 1` loses a container's settings
  for good. `/rm preset` does ask first, so the slash surface is not consistent with itself either.
- **Reachability:** Any player who types `/rm delete <n|name>`.
- **Fix direction:** Route the verb through the same `StaticPopup` the panel uses (it shows outside
  combat, and a preset's confirm already does this).

### F-009: A container that was ever on screen stays clamped to the screen `[correctness]`

- **Where:** `modules/Anchors_Screen.lua:104` `inst.frame:SetClampedToScreen(true)` in
  `Screen.Apply`. `Screen.Detach` (`:108-112`) resets `SetMovable(false)` but never the clamp.
- **Problem:** The clamp outlives the screen mode. It persists when a container switches to frame,
  nameplate or cursor mode, and when a pooled instance is reused for another container.
- **Impact:** A display on a nameplate or unit frame near a screen edge is pushed back on screen, off
  the frame it belongs to. A cursor display near the edge stops following the cursor.
- **Reachability:** Any player who makes a container with *New container* (it starts on screen) and
  then sets *Attach to* to anything else, until the next reload.
- **Fix direction:** Clear the clamp in `Screen.Detach` (`SetClampedToScreen(false)`), next to the
  `SetMovable(false)` it already resets.

### F-010: `Ticker.Removed` cannot be reached in the shipped wiring `[dead-code]`

- **Where:** `modules/Ticker.lua:162-166` (`if not watched[unit] ... then return end`), called at
  `core/RangeMaster.lua:144` right after `NS.Plates.Removed(token)`. That call already released every
  plate instance on the token (`modules/Anchors_Nameplate.lua:237`), and those instances are the only
  watchers of a plate token.
- **Problem:** By the time `Ticker.Removed` runs, the token is never watched, so it always returns at
  its guard. Its header comment describes a send that never happens.
- **Impact:** It misleads maintainers and has no runtime effect.
- **Reachability:** Nobody. No shipping path reaches past the guard.
- **Fix direction:** Remove the call and the function, or keep it and say in the comment that it
  exists only for a future watcher of plate tokens.

### F-011: The Retail client builds a range ladder it never walks `[perf]` `[dead-code]`

- **Where:** `modules/Range.lua:218` `ladder = Compat.RangeLadder()` on every rebuild, while the only
  reader is gated by `:142` `... and Compat.IsForever() then lo, hi = walkLadder(unit) end`.
  `core/Compat.lua:334-341` builds spell rungs for Retail as well, from the `retail` `ladder` lists in
  `defaults/SpellSeeds.lua`. Their own header (lines 15-16) says "Retail's ladder is never walked".
- **Problem:** Wasted work and dead data on Retail.
- **Impact:** A few `IsSpellKnown` and `GetSpellInfo` calls per `SPELLS_CHANGED` burst, and seed
  lists that cannot matter.
- **Reachability:** Every Retail player, at login and on each spell change. The cost is negligible.
- **Fix direction:** Build the ladder lazily on first walk (`currentLadder()` already does this) and
  have `rebuildNow` only drop it (`ladder = nil`). Keep the Retail lists only if a Retail walk is
  planned.

### F-012: The layers-table comment says the addon draws no frames `[naming]`

- **Where:** `core/Constants.lua:68-70` "The v0.1.0 scaffold draws no frame of its own yet; the first
  row is reserved for the range containers".
- **Problem:** The comment dates from the scaffold. The addon now draws containers, plate instances,
  drag handles and the picker overlay.
- **Impact:** It misleads anyone placing a new frame against the stack.
- **Reachability:** A comment, with no runtime effect.
- **Fix direction:** Rewrite the sentence to describe the HUD row as it is built today.

### F-013: The renderer accepts dialog-tier strata the settings row never offers `[layering]`

- **Where:** `modules/Container.lua:101-102` `STRATA = { ..., DIALOG = true, FULLSCREEN = true,
  FULLSCREEN_DIALOG = true, TOOLTIP = true }`, used at `:206`. The row offers only `V.STRATA`
  (`settings/Containers.lua:70-71`, BACKGROUND to HIGH), and `/rm set container.anchor.strata DIALOG`
  is refused (checked in a scratch run).
- **Problem:** The renderer allows more than the schema does. A hand-edited SavedVariables value
  lifts a HUD display into the dialog tiers (frame-layering-§1, anti-pattern #102).
- **Impact:** A HUD display could cover dialogs. This needs a hand edit.
- **Reachability:** Only a player who hand-edits `RangeMasterDB`.
- **Fix direction:** Read the allowed set from `NS.ContainerValues.STRATA`, so the renderer and the
  row cannot disagree, and fall back to `LAYERS.STRATA.HUD`.

## Checked and not raised

- Taint and combat: no hooks; no `SetPoint` on a frame anchored to a secure frame in combat
  (`modules/Anchors_Frame.lua` defers); every range read is under `pcall` and secret-checked
  (`core/Compat.lua:115-120`, `modules/Range.lua:125-130`). LibRangeCheck is called with
  `maxCacheAge = 0`, and its cache entry expires at `updateTime + 0 > currentTime`, so no stale
  bracket is read back.
- Disabled state: `tests/test_disabled.lua` asserts on the mock's registration set, proves each fire
  reached a handler (`__fireUnconditional ... >= 1`) and tests the latch with both hold orders.
- Degradation stubs: Perf, Lifecycle, Bus, Launcher and Compat answer the members the addon calls. The
  Options stub omits `TextRow` and `MASTER_GROUP`, but every caller is inside a page builder, and the
  degraded `RegisterOptionsPage` never registers one, so none is reachable.
- Perf buckets: the five declared buckets are each reached by a real bracket, and `within` matches the
  observed parents.
- Load list: `tests/run.lua` and `tests/perf.lua` derive the addon's files from the TOC and the
  library's from `LibKa0s.xml` (testing-§9).
- Slash validation: `/rm set container.layout.scale 0` clamps to 0.5 and a bogus `anchor.mode` is
  refused (scratch runs), so `CM.SetField`'s type-only check is not reachable with a bad value from a
  player surface.
