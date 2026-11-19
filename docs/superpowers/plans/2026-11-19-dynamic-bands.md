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
| D3 | Rule evaluation in the range memo; Resolve's rule path; Sim | done | `1c407b6` |
| D4 | Schema v2: band rules, convert-everything migration, rule-based class presets | done | `03c5676` |
| D5 | Band editor: Defined by, role, spell override, read-out, Fallback (yards) | done | `80ea9e7` |
| D6 | Review: parallel reviewers, adversarially verified, fixes | done | `4d4c4a6` |
| D7 | Docs, in-game probes in smoke tests, perf scenario, test-case list, badge, push | done | `5c2ff2a` |

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

D3 decisions (taken in the build):

- Band order is kept for every band, yard bands included: the first band that holds wins. A yard band
  (no rule, or a rule Resolve cannot read) holds when the bracket's yard pick is that band. A spell
  band holds on its anchor's true. If the anchor answers nil, the band acts as a yard band. If
  `Resolve` ran every rule before the yards, a caster's yard first band could never win, because
  its ranged spell is also in range at melee distance.
- When no band holds, the yard pick is taken unless that band's own rule contradicts it: a spell band
  whose anchor said false, or a gap band while the ranged or melee anchor says true. A contradicted
  pick, or no bracket at all, reads "unknown", never OOR.
- The melee guard's "verified 20 yd check" is the estimator's own bracket: a melee true is voided
  (made nil) for every class but HUNTER when the bracket's near bound is 20 yd or more. The bracket
  is already built from the verified item and interact checks (on Forever, the 20/30/35 yd items), so
  the guard needs no extra client call.
- The gap's "shorter check" is the bracket's far bound at or under the ranged anchor's reported min,
  or the duel interact distance (index 3, 10 yd). The interact check is not asked under a preview or
  where the client refuses it (spellsOnly). A ranged anchor with no min range has no dead zone, so a
  Retail gap band never holds by rule. The gap reads the class's default melee and ranged anchors, not
  a band's own `spells` list.
- The spell memo is per unit token, then per spell ID, and lives until BeginTick. The chips
  (`InSpellRange`, known cached until rebuild) and the band rules (`RoleInRange`, through
  `Compat.AnchorInRange`) share it, so each spell is asked once per unit per tick. An existing test
  that flipped usability inside one tick now starts a new tick first.
- A band's own `spells` list (the override from the design's band shape) is evaluated now:
  `RoleInRange(role, unit, spells)` resolves it the way a role's list is resolved (first known,
  learned rank). It is cached per list table in a weak-keyed table and wiped at rebuild. Writers
  replace the list rather than mutate it in place: the BandSets writers copy values. D5 must keep
  doing so.
- The steady read re-resolves the band. `inst:PollSpells` now also re-asks the band through Resolve
  for a shown instance with a known or unknown state. An anchor can come into range while the
  LibRangeCheck bracket stays put (the owner's 35-40 case), and without this no RANGE_UPDATED would
  ever repaint the band.
- Previews: a source answers rules through `InRole(role, unit, anchor)`. Sim answers from its distance
  against the anchor's reported min/max (nil with no max). Test mode answers nil, so a rule band
  reads its fallback yards and the 20-25 placeholder lands where it always did (with every chip
  in range, the placeholder would otherwise always read the first spell band).
- `Resolve`'s only caller is `modules/Container.lua`'s resolveBand, which now passes the unit. The
  sounds read the renderer's band and the preview draws through the renderer, so neither calls
  Resolve.

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

D4 decisions (taken in the build):

- Only the OUTERMOST band whose far edge is 20 to 45 yd gets `spell(ranged)` (or `spell(friendly)`).
  Read literally, the rule gives Melee / Ranged's CLOSE, MID and LONG all `spell(ranged)`. Because the
  first band that holds wins (D3), CLOSE would then take every true and MID and LONG could never
  show. The nearer bands stay yard bands and still win by their yards, in band order.
- "A band from 5 to 8 yd directly before an 8 yd band" is read as a band from exactly 5 to exactly 8
  that is not the first and has a band after it (the chain makes the next band start at 8).
- "Used only as a friendly override" means at least one container's `bandSetFriendly` names the set
  and no container's own `bandSet` does. A container with no `bandSet` counts as using the default
  set. "Named Healer" is compared trimmed and case-blind, against "Healer" and the running locale's
  `L["Healer"]`.
- The step normalizes each set first (`BandSets.NormalizeSet`), so a hand-edited set is read in band
  order. The conversion lives in `modules/BandSets.lua` as `BandSets.ConvertSet`, next to the other
  load-pass helpers. `core/Database.lua`'s step only walks the profiles and works out which sets are
  friendly. A band whose `rule` is not a table (junk) is converted, and a rule table is kept as it is.
  Normalizing copies each band, so a band's own `spells` list is a new table after the step (D3's
  per-list cache is wiped at rebuild anyway).
- Presets: Melee / Ranged gets rules too (MELEE spell(melee), LONG spell(ranged), OOR beyond), the same
  set the step makes from its v1 shape. Healer keeps its shape (NEAR yards, FAR spell(friendly), OOR
  beyond). The caster set follows the plan literally: 0-8 CLOSE (yards), 8-40 CAST spell(ranged), 40+
  OOR beyond, with the new locale string `CAST`. It loses its 8-30 / 30-40 split. A stored v1 Caster 40
  set keeps its four bands (CLOSE, MID yards; LONG spell(ranged); OOR beyond).
- "Rule-based class presets" is read as these four presets carrying rules, picked per class by
  `DefaultFor`, as before. No new per-class preset sets are added, which follows the "one class preset
  per class per client" ruling.
- The test "a set with no rule asks no spell" (tests/test_range.lua) built its yard set from the
  Melee / Ranged preset, which now carries rules. It now builds a set from a bands array that has no
  rules.
- `docs/test-cases.md` is not regenerated (left to D7, as in D3).

## D5. Band editor

- `settings/BandSets.lua`: per band a **Defined by** dropdown (Yards / Spell / Dead zone / Beyond the last
  spell band); for Spell a role dropdown and a spell-ID override edit box; a read-only line naming the
  anchor in use and the range the client reports, or "not learned: using N yd"; the yard slider relabelled
  **Fallback (yards)**. Band headers show the rule. Locale strings, refreshers (options-ui-§ refresh rule).
- Tests: each control writes its field, the read-out per resolution state.

D5 decisions (taken in the build):

- One new writer, `NS.BandSets.SetBandRule(id, i, rule?)`: nil makes a yard band; gap, beyond and
  spell(role, spells?) are validated (role one of the three; a list is non-empty whole IDs from 1) and
  stored as a fresh copy holding only those fields, so a band's `spells` is never the caller's table
  (D3's per-list cache). It touches no edge, so it normalizes nothing.
- One new read, `NS.Range.AnchorFor(role, spells?)`: the band's own list's first known spell, else the
  role's anchor. `RoleInRange` now goes through it, so the read-out names exactly what a tick asks.
- Defined by on a band switching to Spell takes melee for the first band and ranged elsewhere, and keeps
  the role and list of a band that is already a spell band. A role change keeps the override list.
- The spell override is one edit box of comma-separated IDs (empty: the class's anchors). A part that
  is not a whole ID refuses the whole entry aloud and keeps the stored list. No icon/name preview: the
  read-out already names the spell in use.
- The read-out (a note row, spell bands only): "Now: Arcane Shot (3044), 8-41 yd", "melee range" for a
  reported max of 0, "range not reported" for none, "spell N" when the client gives no name, and
  "Not learned: using 5-30 yd" (the band's fallback span) when nothing resolves, which also covers a
  druid out of Cat and Bear. `source = "reported"` is not stored: the read-out reads the resolver.
- The slider reads **Fallback (yards)** only on a band with a rule; a yard band keeps **Up to (yards)**,
  because its yards are its definition there, not a fallback.
- Headings: "Band 2: 5-40 yd CAST (Spell: Ranged)", "(Dead zone)", "(Beyond the last spell band)"; a yard
  band's heading is unchanged. The Containers page's band spans are not touched (not in the plan).
- Refresh: the page subscribes to `ANCHORS_CHANGED` beside `BANDSETS_CHANGED` (both redraw on the next
  frame), so the read-out follows a talent, form or level change. The message register row in
  docs/ARCHITECTURE.md names the new subscriber. docs/settings-panel.md is left to D7, as the plan says.

## D6. Review fixes

Twelve confirmed findings (three of them the same migration bug), fixed in one pass.

D6 decisions (taken in the fix pass):

- `beyond` is ruled out by the yards when the bracket's far bound is UNDER the beyond band's fallback
  `from` (a bracket ending exactly at `from` may still reach it, so the boundary keeps OOR). That is
  looser than the review's suggestion (the near bound at or past `from`), on purpose: spells still beat
  yards wherever the yards leave beyond possible (the owner's 35-40 case with every anchor false still
  reads OOR on a 35+ beyond band). A ruled-out beyond falls to the yard pick and its contradiction test,
  so the review's 5-10 yd case reads "unknown". This refines research part 2's "an unconfirmed gap falls
  to beyond", which did not cover yards that contradict it.
- Sim reads an anchor's reported max range of 0 or less as a 5 yd melee reach (the client's combat
  range), not as no answer, so Sim's MELEE band shows on every melee anchor.
- A rebuild re-resolves at once every band spell list a read has asked since the last one and folds
  the change into ANCHORS_CHANGED's test, so the cache is no longer only wiped at rebuild (D3).
- docs/settings-panel.md's Bands paragraph is brought up to D5's editor here (a review finding); D7's
  doc pass still owns the rest.

## D7. Docs, probes, perf, test list

D7 decisions:

- The in-game probes are smoke checks RANGE-6 to RANGE-11 (reported range under Hawk Eye, Auto Shot at
  38 yd with Hawk Eye 0/3 and 3/3, rank IDs, which event a talent point fires, Retail Wrath with Astral
  Influence, and the override-known and unarmed Auto Shot questions from D1 and research part 2), and
  the band checks BANDS-6 to BANDS-10 (the rule controls, the read-out, the owner's Hawk Eye case at
  35-41 yd, the dead zone, the v1 -> v2 conversion). All are listed under Pending sign-off.
- The talent-event probe is a one-line `/run` frame (under the chat's 255 characters), since the
  rebuild logs nothing to the debug console.
- The three undocumented client behaviors (talented reported ranges, rank-1 IDs, the talent event) are
  recorded in docs/midnight-quirks.md as unmeasured quirks; the Retail nameplate secrecy in restricted
  content stays a research open question, not a quirk, as no code depends on it beyond the nil path.
- The perf scenario is `render.plates.rules.quiet` / `render.plates.rules` in tests/perf.lua (outside
  the gate): twenty plates on the Forever hunter rule set. A quiet tick is near-free (a few bytes) and asks at
  most one range call per anchor per plate; a moving tick's allocation equals a yard set's for the
  same AUTO <-> OOR swap (measured with the rules stripped), so the rule path adds time, not garbage.
- New Known Limitations rows in docs/ARCHITECTURE.md: undocumented talented ranges, the Retail gap
  band, friendly units and melee reach, and D6's beyond-yields-to-yards behavior left for the owner.

## D6, D7

As the previous plan's review and wrap-up: parallel reviewers (correctness, standard conformance, tests and
docs), each finding adversarially verified, one fix pass; then every doc that names bands or the range
engine (docs/schema.md, settings-panel.md, data-flow.md, module-map.md, ARCHITECTURE.md, compat-layer.md,
midnight-quirks.md, smoke-tests.md with the owner's in-game probes, README), test-cases.md regenerated, the
badge, a 20-plate perf scenario, the gate, push.

## Follow-up (2026-11-19, after the merge): beyond shows OOR

The owner ruled that when every spell says out of range the display reads OOR, not unknown, wherever the
yards put the bracket (the band-matrix workbook showed 30-40 yd unknown on most classes). `beyondHolds`
no longer yields to the beyond band's fallback yards; it still yields while the bracket reaches into a gap
band's yards, so the hunter dead zone is never called OOR on a guess. Branch
`fix/2026-11-19-beyond-shows-oor`.
