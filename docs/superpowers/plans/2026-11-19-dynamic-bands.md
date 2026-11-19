# Plan: spell-driven dynamic band sets (2026-11-19)

Branch `feat/2026-11-19-dynamic-bands` (off `master` at `25f7e15`). Push after each milestone; merge only
on the owner's go-ahead. Resumable: the ledger below is the checkpoint. A milestone is done when its row
reads **done** with its commit and the green gate passed at that commit: `lua tests/run.lua`,
`KA0S_KIT_CLIENT=forever lua tests/run.lua`, `~/.claude/dev-copilot/bin/ka0s-bounded luacheck .` (0/0).
Every `.lua`/`.md` file is CRLF, ending in CRLF.

Research of record: `docs/superpowers/specs/2026-11-19-dynamic-bands-research.md` (part 2, the critic,
overrides part 1 where they disagree).

## The owner's rulings (2026-11-19)

- **Mechanism: the hybrid.** A band may carry a spell RULE. Membership is decided every tick by asking
  the class's anchor spells "in range?" (`C_Spell.IsSpellInRange` through the Compat shims), which follows
  talents, gear and auras without knowing a number. Yards stay as each band's FALLBACK (used when its
  anchor is not learned, unusable, or answers nil/secret) and for labels. Pure yard bands keep working.
- **Migration: convert everything.** A schema step turns every stored band set, custom ones included, into
  rule bands where a band maps to a role; its yard numbers stay as the fallback (see D4).
- **Standard:** the owner chose "change the standard" for the nested rule table, but no rule of the
  standard is broken: the band editor is a bespoke editor (options-ui, U-05e) and savedvariables puts no
  limit on nested stored data. So: no deviation row and no upstream change; reported to the owner.
- Decisions taken under the run's "use your best judgement": no MARK (Hunter's Mark) band; a caster's
  first band stays a yard band (no baseline melee spell); one class preset per class per client (no spec
  variants); no runtime wago.tools data; no UNIT_AURA trigger (predicates already follow auras).

## Design (summary; detail in the research doc)

- **Band shape** (schema v2): `band.rule = nil | { type = "spell", role = "melee"|"ranged"|"friendly",
  spells = nil|{id,...} } | { type = "gap" } | { type = "beyond" }`. `from`/`to` stay finite yards (the
  fallback); `spells` nil means the class's default anchors for the role, a list overrides them. A rule
  names a ROLE, not a spell, so one set serves every class in a shared profile; a role this character's
  class has no anchor for is unresolved and the band falls back to its yards.
- **Anchors**: `NS.SpellSeeds[client][class].anchors = { melee = {...}, ranged = {...}, friendly = {...} }`,
  ordered fallback lists (research part 1 section 6, corrected by part 2: e.g. drop Mongoose Bite, a
  reactive spell). Druid melee anchors are form-keyed (Cat: Claw/Shred, Bear: Maul/Growl/Bash).
- **Resolution at rebuild** (debounced `NS.Range.Rebuild`): per role, the first anchor that is known; each
  resolved to the CURRENT rank's ID by name through `C_Spell.GetSpellInfo(name).spellID` (critic 10),
  override-resolved, with its client-reported min/max range kept for labels (`source = "reported"`).
- **Evaluation per tick** inside the Range memo (shared with the spell chips, one call per spell per unit
  per tick), in band order: `spell(role)` holds on a `true` from the role's anchor (and it is usable);
  `gap` holds when the ranged anchor says `false`, the melee anchor does not say `true`, and a shorter check
  confirms near (interact distance, a verified item, or the LRC bracket's max at or under the ranged
  anchor's min); `beyond` holds when every spell band's anchor said `false` and no gap held. A nil answer
  never counts as false: that band falls back to its yards, and with nothing to decide the result is
  "unknown", never OOR. A non-hunter melee `true` is voided when a verified 20 yd check says out of range
  (the unusable-spell false positive, docs/midnight-quirks.md).
- **Triggers** (all `ifValid`, into the debounced rebuild): SPELLS_CHANGED (today), CHARACTER_POINTS_CHANGED,
  PLAYER_TALENT_UPDATE, TRAIT_CONFIG_UPDATED, ACTIVE_TALENT_GROUP_CHANGED, PLAYER_SPECIALIZATION_CHANGED,
  LEARNED_SPELL_IN_SKILL_LINE, PLAYER_LEVEL_UP, UPDATE_SHAPESHIFT_FORM, PLAYER_EQUIPMENT_CHANGED,
  CVAR_UPDATE, UNIT_PET (already registered: wire it to the rebuild too), plus LibRangeCheck's
  CHECKERS_CHANGED callback. A rebuild announces a change only when a resolved anchor or range moved.
- **Preview modes**: Sim evaluates the rules against its fake distance using the anchors' reported ranges;
  Test mode keeps its placeholder.

## Ledger

| # | Milestone | Status | Commit |
|---|---|---|---|
| D0 | Research doc, this plan | done | `6a76078`, this commit |
| D1 | Compat anchor shim and per-class anchor seeds, both clients | done | `6ef1336` |
| D2 | Anchor resolver and the rebuild triggers | done | `133062e` |
| D3 | Rule evaluation in the range memo; Resolve's rule path; Sim | todo | |
| D4 | Schema v2: band rules, convert-everything migration, rule-based class presets | todo | |
| D5 | Band editor: Defined by, role, spell override, read-out, Fallback (yards) | todo | |
| D6 | Review: parallel reviewers, adversarially verified, fixes | todo | |
| D7 | Docs, in-game probes in smoke tests, perf scenario, test-case list, badge, push | todo | |

## D1. Compat anchor shim and seeds

- `core/Compat.lua`: `Compat.AnchorInRange(id, unit)` built on the existing IsSpellKnown / IsSpellUsable /
  SpellInRange shims (no second wrap of the client call), plus `Compat.CurrentSpellID(id)` (name lookup to
  the current rank and override). docs/compat-layer.md's shim list and count follow.
- `defaults/SpellSeeds.lua`: an `anchors` sub-table per class per client (research section 6 with the
  critic's corrections; Retail DH Disrupt 183752 is melee, not 20 yd; fix the stale ladder entry).
- Tests under both kit profiles: the shim's answers (true/false/nil, secret = nil, unknown spell = nil),
  the current-rank lookup, every anchor list non-empty for its class's ranged role.

D1 decisions (taken in the build):

- `CurrentSpellID` takes an override (`C_Spell.GetOverrideSpell`) only when `IsSpellKnown` says the
  player knows the override, so whatever ID it returns can pass `AnchorInRange`'s known gate. Whether
  the client calls an override ID "known" is unverified (an in-game probe for D7). It answers nil when
  the client has no such spell, and the seed ID itself when the name lookup answers nothing.
- `AnchorInRange(id, unit)` takes the ID `CurrentSpellID` resolved at rebuild and does no name lookup
  per tick. It answers nil unless the spell is known and usable right now.
- Anchor roles are melee, ranged and friendly only. There is no `long` role, because the owner ruled out
  a MARK band. Druid melee is a map of form key to list, `{ cat = {...}, bear = {...} }`. D2 maps
  `GetShapeshiftFormID` to those keys.
- Forever Paladin has no melee anchor: Judgement 20271 is 0-10 yd, too far for a melee band. Its first
  band stays a yard band, as for the casters. Retail Bear drops Growl, a 30 yd taunt there.
- Retail DH: Disrupt 183752 is a melee anchor and still a chip. The ladder drops it for Torment 185245.

## D2. Anchor resolver and triggers

- `modules/Range.lua` (or a new `modules/Anchors_Spells.lua`-style file if Range.lua would pass its size
  budget; check layout-§1): per role the resolved anchor `{ id, name, minRange, maxRange }` or nil, keyed
  by druid form, rebuilt in the existing debounced Rebuild; `NS.Range.Anchor(role)` reads it.
- `core/RangeMaster.lua` LIFECYCLE_EVENTS gains the trigger events; tests reading `NS.__lifecycleEvents`
  follow. LRC CHECKERS_CHANGED subscribed under pcall when the library offers callbacks.
- Tests: resolution picks the first known anchor, the current rank, form switching, a rebuild after each
  trigger, no announcement when nothing moved.

D2 decisions (taken in the build):

- The resolver stays in `modules/Range.lua` (now 370 lines, far under layout-§1's 1500-line cap).
  `NS.Range.Anchor(role)` answers `{ id, name, minRange, maxRange }` or nil; a secret or non-number
  range is nil, the anchor still resolved. It resolves lazily on the first read when no rebuild ran.
- The announcement is a NEW message, `ANCHORS_CHANGED` (sender `modules/Range.lua`), not
  `BANDSETS_CHANGED`, whose register names `modules/BandSets.lua` as its one sender. The renderer
  repaints on it; the Bands page's read-out subscribes in D5. Five messages, still under the ten that
  would require `docs/message-bus.md`.
- Druid form: every form's anchor is resolved at rebuild, and the one in use is picked on each read
  from `NS.Compat.ShapeshiftFormID()` (a new shim, 13; the frame reads are now 14 to 17, 21 shims),
  so a shift is followed before the debounce fires. Form IDs 1 = cat, 5 and 8 = bear (8 is Dire Bear
  where a client tells it apart); any other form has no melee anchor. The form's pick is part of the
  change signature, so `UPDATE_SHAPESHIFT_FORM`'s rebuild announces a shift.
- Triggers: the nine new events all route to `OnSpellsChanged` (ifValid). `CVAR_UPDATE` rebuilds only
  for `ShowAllSpellRanks`, as LibRangeCheck-3.0 filters it. `UNIT_PET` rebuilds for the player's pet
  only. `CHARACTER_POINTS_CHANGED` is never filtered on its count (critic 5).
- LibRangeCheck's `CHECKERS_CHANGED` is subscribed in `RegisterLifecycleEvents` and dropped in
  `UnregisterLifecycleEvents` (`addon:SubscribeRangeLibrary`, pcall), so a stood-down addon hears
  nothing. The harness now loads the real vendored `CallbackHandler-1.0` before the estimator, as the
  TOC does, with a call-through `securecallfunction` in `tests/wow_mock.lua`.

## D3. Rule evaluation

- `NS.Range.RoleInRange(role, unit)` through the per-tick memo (and the chips share it).
- `NS.BandSets.Resolve(setId, state, minYd, maxYd, unit)` evaluates rule bands first, then the yard path
  against the fallback yards; every caller (modules/Container.lua's resolveBand, sounds, preview) passes
  the unit. Unknown stays unknown.
- Sim mode (modules/Sim.lua / Preview.lua) answers the rules from its fake distance.
- Tests: the owner's case (bracket 35-40, Arcane Shot true: AUTO, not OOR), the dead zone (gap), an
  unlearned anchor (fallback yards), a nil/secret answer (fallback, never OOR), the melee guard, form
  gating, Sim.

## D4. Schema v2

- `core/Database.lua` step `to = 2`, every stored profile (savedvariables rules): every band set converted.
  Per set, in band order: the last open-ended band gets `beyond`; a first band ending at 5 yd or less gets
  `spell(melee)`; a band from 5 to 8 yd directly before an 8 yd band gets `gap`; a band whose far edge is
  20 to 45 yd gets `spell(ranged)`, or `spell(friendly)` in a set used only as a friendly override or named
  Healer; any other band stays a yard band. Yards untouched (they are the fallback). Idempotent.
- `defaults/BandSetPresets.lua`: the presets carry rules (Forever Hunter: MELEE spell(melee), DEAD gap, AUTO
  spell(ranged), OOR beyond; Retail Hunter without DEAD; casters: a yard first band, CAST spell(ranged),
  OOR beyond; Healer: friendly). docs/schema.md.
- Tests: the conversion of each preset shape and of a custom set, idempotence, a fresh profile.

## D5. Band editor

- `settings/BandSets.lua`: per band a **Defined by** dropdown (Yards / Spell / Dead zone / Beyond the last
  spell band); for Spell a role dropdown and a spell-ID override edit box; a read-only line naming the
  anchor in use and the range the client reports, or "not learned: using N yd"; the yard slider relabelled
  **Fallback (yards)**. Band headers show the rule. Locale strings, refreshers (options-ui-§ refresh rule).
- Tests: each control writes its field, the read-out per resolution state.

## D6, D7

As the previous plan's review and wrap-up: parallel reviewers (correctness, standard conformance, tests and
docs), each finding adversarially verified, one fix pass; then every doc that names bands or the range
engine (docs/schema.md, settings-panel.md, data-flow.md, module-map.md, ARCHITECTURE.md, compat-layer.md,
midnight-quirks.md, smoke-tests.md with the owner's in-game probes, README), test-cases.md regenerated, the
badge, a 20-plate perf scenario, the gate, push.
