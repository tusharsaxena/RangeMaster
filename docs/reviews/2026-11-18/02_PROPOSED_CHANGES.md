# RangeMaster v0.1.0: proposed changes (2026-11-18)

**Standard:** Ka0s WoW Addon Standard v2.113.0 (2026-11-16), from the sibling checkout
`../WowAddonStandards` at `1f5767f338ce7ecd3d7a2b698baee8920eea0400` (clean, equal to `origin/master`).
**Finding source:** `01_FINDINGS.md` in this folder (F-001 to F-013).

## HLD

### Theme A: The first draw does not depend on the skin (F-001)

- **What:** `OnEnable` asks the container registry for one apply, so stored containers draw at login
  however the skin is configured.
- **Why:** Today the first `CONTAINERS_CHANGED` is a side effect of `NS.ApplySkinIgnore` changing
  something. That ordering is accidental, and it breaks for a reachable setting.
- **Rejected alternative:** Making `NS.ApplySkinChoice` always fire `OnLooksChanged`. That would
  repaint every skinned surface on every login just to start the renderer, and it couples two
  unrelated concerns.
- **Trade-off:** On the default config, two `RequestApply` calls may now land before the first frame.
  They coalesce into one flush (`CM.RequestApply` arms one timer), so the cost is zero.

### Theme B: The picker leaves the game's frames alone (F-002)

- **What:** The pick is confirmed with Enter and canceled with Escape. Mouse presses no longer
  pick or cancel.
- **Why:** A non-mouse overlay cannot stop the click reaching the frame under it.
- **Rejected alternative:** A mouse-enabled full-screen overlay. It is a click catcher, the shape
  frame-layering-§4 retired, and `GetMouseFoci()[1]` would then always be the overlay.

### Theme C: Overlapping displays stack whole (F-003, F-013)

- **What:** Each container instance gets a deterministic base level with a fixed stride, named in
  `NS.Constants.LAYERS`. The renderer's strata whitelist becomes the settings row's own value set.
- **Why:** frame-layering-§3 *Peers stack whole*, frame-layering-§1 and §5.
- **Trade-off:** The levels a display can reach grow with the instance count, so the stride times
  the instance count must stay under the frame-level ceiling. This is bounded below.

### Theme D: One writer per registry (F-006)

- **What:** A band-set delete reassigns containers through `NS.CM.SetField`.
- **Why:** architecture-§5: one runtime writer per registry, and member fields go through the seam.

### Theme E: Spell chips follow the character (F-004)

- **What:** A container stores `elements.spells.list` only once the player has chosen one. Until
  then, the chips read the current character's class seeds at render time.
- **Rejected alternative:** Re-seeding on login. It would overwrite a stored list without asking,
  which savedvariables-§5 rules out.
- **Deferred alternative:** A chip-list editor. It is the better long-term answer (options-ui
  IdList), but it is a feature. It should be filed as an issue rather than folded into this fix.

### Theme F: Evidence that can fail (F-005)

- **What:** A dormant-bracket scenario over the hot paths, counting calls.

### Theme G: Cleanup (F-007, F-008, F-009, F-010, F-011, F-012)

- Localize two lines, confirm `/rm delete`, clear the screen clamp on detach, remove the unreachable
  `Ticker.Removed`, stop building the Retail ladder, and fix one stale comment.

## Upstream change-set

None. No defect was found under `libs/` or `tests/_kit/`. Vendor sync and the cross-addon pass are
clean at LibKa0s `v1.105.0`.

## LLD

### C-01: First apply at login (F-001)

- **File:** `core/RangeMaster.lua`, `addon:OnEnable` (lines 44-55).
- **Sketch:**

```lua
    NS.SyncEnabledHold()
    if not NS.IsStoodDown() then self:RegisterLifecycleEvents() end
    -- The stored containers draw now, whatever the skin did (it is no trigger for the first apply).
    -- Stood down, this only marks the apply owed; the stand-up's CM.StandUp runs it.
    NS.CM.RequestApply()
```

- **Test:** Add a case to `tests/test_container_render.lua`. Store a container through the raw
  profile, set `skin.ignorePanel = false`, re-run `OnInitialize` and `OnEnable`, fire timers, and
  assert `NS.Container.Get(id) ~= nil`, with
  `-- red under: OnEnable's RequestApply removed (the first draw rides on the skin's callback)`.
  The pass count moves from 610 to 611, so `docs/test-cases.md` and the README `[tests]` badge move in
  the same change (testing-§5).
- **Risk:** Low. `RequestApply` is idempotent and coalesced.

### C-02: Keyboard-confirmed frame pick (F-002)

- **File:** `modules/FramePicker.lua`, `onUpdate` (lines 112-122) and `onKeyDown` (lines 124-131).
- **Sketch:** `onUpdate` only tracks the hovered frame and remembers its name. It no longer reads
  `IsMouseButtonDown`. `onKeyDown` handles `ENTER` (pick the remembered name, swallow the key with
  `SetPropagateKeyboardInput(false)` out of combat) and `ESCAPE` (cancel, as today). Every other key
  propagates.
- **Locale:** Replace "Left-click to pick, right-click to cancel" and "Point at a named frame.
  Right-click to cancel." with Enter and Escape wording in `locales/enUS.lua`. Update the
  `/rm pick` reply in `settings/Containers.lua` and the *Pick on screen* tooltip. `tests/test_locale.lua`
  will see the key changes.
- **Tests:** The existing picker cases that drive `IsMouseButtonDown` must be rewritten to send
  `OnKeyDown("ENTER")`. That is an intended behavior change, not a weakened test. The case count
  stays the same unless a case is added for "a left press neither picks nor cancels".
- **Risk:** Medium. This is a UX change, so the smoke list carries it.

### C-03: Per-instance level base (F-003)

- **Files:** `core/Constants.lua` (LAYERS), `modules/Container.lua` (`newInstance`, `applyFrame`),
  `modules/Style.lua` (unchanged API).
- **Sketch:**

```lua
-- core/Constants.lua
    LEVEL = { FILL = 1, BORDER = 2, OVERLAY = 4, HANDLE = 50, STRIDE = 60, BASE = 10 },
-- modules/Container.lua
local nextSlot = 0
local function newInstance()
    local root = CreateFrame("Frame", nil, UIParent)
    root:SetFrameStrata(LAYERS.STRATA.HUD)
    nextSlot = nextSlot % 100 + 1                                  -- bounded under the level ceiling
    root:SetFrameLevel(LAYERS.LEVEL.BASE + nextSlot * LAYERS.LEVEL.STRIDE % 9000)
    ...
```

  The children keep their `Style.Stack` offsets, which are now relative to a distinct base. The stride
  (60) covers HANDLE (50). Pooled instances keep their slot, so a reused instance does not move.
- **Constraint:** frame-layering-§3 (deterministic per-instance base, stride at least the band
  height) and frame-layering-§5 (the stride and base are named in the one LAYERS table, and
  `tests/test_layers.lua` keeps literals out). Frame levels top out at 10000, so the slot count
  wraps well under that.
- **Risk:** Medium. Check the drag handle (`level = LAYERS.LEVEL.HANDLE`, relative) and the TestStrip
  dock in the smoke list.

### C-04: Renderer strata from the row's values (F-013)

- **File:** `modules/Container.lua:101-102, 206`.
- **Sketch:** Delete the local `STRATA`. At `applyFrame` use
  `local V = NS.ContainerValues; local ok = V and V.STRATA and V.STRATA[c.anchor.strata]`, then
  `root:SetFrameStrata(ok and c.anchor.strata or LAYERS.STRATA.HUD)`. `NS.ContainerValues` loads
  later (settings), but it is read at call time, so the load order is unaffected.
- **Risk:** Low.

### C-05: Band-set delete through the container writer (F-006)

- **File:** `modules/BandSets.lua`, `reassign` (lines 387-394).
- **Sketch:**

```lua
local function reassign(p, id, target, named)
    for _, cid in ipairs(NS.CM.List()) do
        local c = NS.CM.Get(cid)
        if c.bandSet == id then NS.CM.SetField(cid, "bandSet", target) end
        if c.bandSetFriendly == id then NS.CM.SetField(cid, "bandSetFriendly", named and target or nil) end
    end
end
```

  `CM.SetField`'s `acceptable` check for `bandSet` and `bandSetFriendly` requires the target set to
  exist. The set is removed before `reassign` runs and the target is chosen from the survivors, so the
  check passes. `CM.SetField` asks for an apply, which coalesces.
- **Risk:** Low. `tests/test_bandsets.lua` delete cases cover it.

### C-06: Chips resolve per character until chosen (F-004)

- **Files:** `modules/ContainerManager.lua` (`CM.Create` stops seeding: `list` stays `{}`, or a
  `nil`-able marker), and `modules/Container.lua` `spellList` plus `modules/Elements_Spells.lua`
  `Spells.Style`. When the stored list is empty, both read
  `NS.SpellSeeds[ClientKey()][PlayerClass()].chips`.
- **Migration:** Existing v0.1.0 profiles hold seeded lists, but v0.1.0 has not shipped, so no
  migration step is needed. If this ships after a release, add a `SCHEMA_STEPS` entry that clears a
  list equal to its class's seed (core/Database.lua; savedvariables-§1).
- **Docs:** Update `docs/ARCHITECTURE.md` Known Limitations and `docs/schema.md`.
- **Risk:** Medium. The Advanced preset (`modules/Presets.lua:106`) and the icon indicator
  (`modules/Elements_Indicator.lua:34-38`) read `list[1]`, so both switch to the same resolver.

### C-07: A hot-path dormant-bracket scenario (F-005)

- **File:** `tests/perf.lua` (lines 240-252 and a new block).
- **Sketch:** Wrap `mocks.debugprofilestop` and `NS.Perf.Note` with counters. With `NS.Perf.on = false`,
  run 1000 moving ticks over the ten containers and the twenty plates, then assert both counters are 0.
  Add `-- red under: a bracket that reads debugprofilestop before testing Perf.on`. Keep
  `probeOverheadOff` and `probeOverheadOn` as orientation figures.
- **Counts:** Scenarios are not test cases (testing-§7), so the inventory and badge do not move.

### C-08: Localize the two chat lines (F-007)

- **Files:** `core/SkinSetup.lua:467` becomes `local RELOAD_LINE = NS.L["Reload your interface (/reload) to finish changing the skin."]`,
  and `settings/Schema.lua:315` gets `NS.L[...]`. Add both keys to `locales/enUS.lua`.
- **Constraint:** localization-§1 (the `NS.L` seam). `locales/enUS.lua` loads first, so a file-scope
  read is safe.

### C-09: `/rm delete` asks first (F-008)

- **File:** `settings/Slash.lua:268-274`.
- **Sketch:** After resolving the id, show `RANGEMASTER_DELETE_CONTAINER` with `popup.data = id`, as
  `settings/Containers.lua:327-332` does. Its `OnAccept` already prints the line.
- **Tests:** `tests/test_slash.lua` cases asserting an immediate delete must accept the popup through
  the mock instead. That is a behavior change, not a weakened test.

### C-10: Clear the clamp on detach (F-009)

- **File:** `modules/Anchors_Screen.lua:108-112`. Add `inst.frame:SetClampedToScreen(false)` to `Screen.Detach`.
- **Test:** In `tests/test_anchors_screen.lua`, a screen container switched to `cursor` is no longer
  clamped. This adds one case (pass count moves, so the inventory and badge move too).

### C-11: Remove the unreachable `Ticker.Removed` (F-010)

- **Files:** `modules/Ticker.lua:13-14, 160-166`, `core/RangeMaster.lua:144`, and the header comment at
  `core/RangeMaster.lua:136-139`.
- **Tests:** If a suite calls `NS.Ticker.Removed` directly, that case goes with the function. The
  count moves, so the inventory and badge move in the same change.

### C-12: No Retail ladder (F-011)

- **File:** `modules/Range.lua:215-221`. `rebuildNow` sets `ladder = nil` and lets `currentLadder()`
  rebuild it on the first Forever walk. Optionally drop the `retail` `ladder` lists from
  `defaults/SpellSeeds.lua`, which keeps the whole-list shape clients-§5 asks for.

### C-13: Stale comment (F-012)

- **File:** `core/Constants.lua:68-70`. Rewrite it to describe the containers, plate instances,
  handle and picker rows as they are built today.

## Standards conformance

| Change | Constraint | New deviation? |
|---|---|---|
| C-01 | architecture-§5 (the registry's writer asks for the apply); slash-commands-§7 (a stood-down addon arms no timer: `RequestApply` returns before arming) | none |
| C-02 | frame-layering-§4 ruled out the mouse-enabled overlay; the combat refusal stays (events-frames-taint) | none |
| C-03 | frame-layering-§3 (Peers stack whole), frame-layering-§5 (one LAYERS table, no literal levels) | none |
| C-04 | frame-layering-§1 and anti-pattern #102 (no dialog tiers for a HUD) | none |
| C-05 | architecture-§5 (one runtime writer per registry) | none |
| C-06 | savedvariables-§5 (a stored choice survives); clients-§5 (seed lists declared whole) | none |
| C-07 | performance-§2 and §9 (zero-overhead evidence; deterministic quantities only, no wall clock) | none |
| C-08 | localization-§1 and §3 | none |
| C-09 | slash-commands-§3 (the host's COMMANDS table keeps its handler) | none |
| C-10 to C-13 | none specific | none |

**Watch list:** No change here should move a function over CCN 15. C-02 slightly reshapes
`onUpdate` and `onKeyDown`, which the next release's regeneration should confirm.
