# Research: spell-driven dynamic band sets (2026-11-19)

The deep-research run behind the owner's request (dynamic band edges from spell range checks, per class, talent aware). Part 1 is the synthesized design proposal; part 2 is an independent critic's corrections, which override part 1 where they disagree. Nothing here is built yet; the owner's decisions and the build plan follow in a plan file.

## Part 1. Design proposal: spell-driven dynamic band sets for RangeMaster

Status: proposal only. Nothing in the repo was changed.
Branch context: `feat/2026-11-19-presets-dot-styles`. Schema is v1 today.
Clients: Retail 12.1.5 (`wow` 12.1.5.70961) and WoW Forever 1.60.1 (`wowf` 1.60.1.70959).

---

## 1. Executive summary

**The cause of the owner's bug.** The bracket is not wrong. The band edge is.

- A hunter with Hawk Eye 3/3 standing about 38 yd away gets an honest LibRangeCheck (LRC) bracket of 35-40.
- The Forever Hunter preset has AUTO `to = 35` and uses `matchBy = "max"`. Since 40 > 35, the band resolves to OOR (`modules/BandSets.lua:161-175`, `defaults/BandSetPresets.lua:360-390`).
- The 5/8/35 edges are exactly the untalented DB2 values. Arcane Shot 3044 and Auto Shot 75 use SpellRange 114 "Hunter Range", 8-35 ([SpellMisc](https://wago.tools/db2/SpellMisc/csv?build=1.60.1.70959), [SpellRange](https://wago.tools/db2/SpellRange/csv?build=1.60.1.70959)).
- Hawk Eye (spell 19498, flat +6, aura 107, misc 5) moves the max to 41 ([SpellEffect](https://wago.tools/db2/SpellEffect/csv?build=1.60.1.70959)).

**What works on both clients**

- `C_Spell.IsSpellInRange(spell, unit)` returns true, false or nil. It exists with the same shape on Retail and Forever, and neither client's generated docs give it a `SecretReturns` flag ([live docs](https://raw.githubusercontent.com/Gethe/wow-ui-source/live/Interface/AddOns/Blizzard_APIDocumentationGenerated/SpellDocumentation.lua), [forever docs](https://raw.githubusercontent.com/Gethe/wow-ui-source/forever/Interface/AddOns/Blizzard_APIDocumentationGenerated/SpellDocumentation.lua)).
- Its answer includes talents ("The result accounts for talents", [wiki](https://warcraft.wiki.gg/wiki/API_IsSpellInRange)). It is the only range answer documented to include talent modifiers.

**What is not known**

- Whether `C_Spell.GetSpellInfo(id).maxRange` returns the talented range is **UNVERIFIED**, and the evidence points both ways (section 3).
- No API returns a "current max range" other than that number ([Gethe docs grep](https://raw.githubusercontent.com/Gethe/wow-ui-source/live/Interface/AddOns/Blizzard_APIDocumentationGenerated/SpellDocumentation.lua)).
- Computing ranges offline from DB2 does not work on Forever. Its DB2 keeps only the max-rank value on the rank-1 ID. Hawk Eye 19499 and 19500 have no SpellEffect rows, so partial ranks cannot be known.

**What is not possible**

- A true distance in yards. The design spec rules this out as a non-goal (`docs/superpowers/specs/2026-11-18-rangemaster-design.md:34-44`).
- A melee edge as a number. Melee reach is `max(5, reachA + reachB + 4/3)`, plus 8/3 yd while both units move ([TrinityCore Unit.cpp](https://github.com/TrinityCore/TrinityCore/blob/master/src/server/game/Entities/Unit/Unit.cpp), an emulator model).
- Telling the dead zone from OOR with a single min-range spell. A false from Auto Shot means either one.

**Recommendation: a hybrid.**

1. **Band membership comes from the spells.** A band can carry a spell rule ("anchor role answers in range", "gap between two spell bands", "beyond the last spell band"). The rule is evaluated per tick from `IsSpellInRange` on per-class anchor spells, the way AppelSwingsForever does it. This is talent-, gear-, weapon- and aura-correct by construction. Hawk Eye at 38 yd paints AUTO without anyone knowing the number 41.
2. **Yards are derived for display and fallback only.** Each spell band's yard edges are read from `GetSpellInfo` of the active anchor at rebuild time. They are used for labels and for the case where the anchor gives no answer. They are trusted only once the in-game probe (M13) confirms they include talents on that client. Otherwise the stored yard number stays as the fallback.
3. **Pure-yard bands remain**, unchanged, for users who want them.

---

## 2. How competitors do it, and what we borrow

| Addon | Model | Borrow? |
|---|---|---|
| **AppelSwingsForever** v1.10.2 (the "AppelSwing" the owner means; [CurseForge](https://www.curseforge.com/wow/addons/appelswings); local `/mnt/g/.../AppelSwingsForever/Bands.lua`) | Bands are spell predicates. **MELEE**: the class melee spell is in range and Auto Shot (75) is not. **DEAD**: Auto Shot is false, melee is not true, and an item at 20 yd or nearer is in range. **MAX**: Auto Shot in range ("Hawk Eye already widens it"). **MARK**: Hunter's Mark 1130. Otherwise **OOR**. Casters: MAX = any of one long-range spell per talent tree is in range (MAGE 133/116, WARLOCK 686/172, PRIEST 585/8092/589, SHAMAN 403, DRUID 5176/8921). It queries `IsSpellInRange` by **name** first, then by ID. It voids a melee "true" when the 20 yd items say out of range, because Claw in caster form answered "in range" from 40 yd. Druid melee is asked only in its own form. Yards.lua builds numeric rungs from the spellbook (minRange 0, maxRange > 5), drops any "untalented" number that disagrees with the verified items, and rebuilds 0.5 s after SPELLS_CHANGED. | **Yes, the core idea.** Also the melee false-positive guard, per-form anchors, one anchor per talent tree, and name-first queries. |
| **RangeLens** (Forever, MIT; [GitHub](https://github.com/jonlipin/range-lens)) | Re-reads each spell's min and max on SPELLS_CHANGED, CHARACTER_POINTS_CHANGED, PLAYER_TALENT_UPDATE and TRAIT_CONFIG_UPDATED, registering each under pcall. Queries by name. Its `TooClose` test asks a shorter checker inside the spell's max to tell "too close" from "too far". | **Yes.** TooClose for the dead zone, and the event set. |
| **LibRangeCheck-3.0** MINOR 39 (vendored = [upstream](https://github.com/WeakAuras/LibRangeCheck-3.0)) | Per-class spell IDs become a checker list with ranges taken from `GetSpellInfo` (rounded). Min-range spells are paired with a disambiguating checker. Re-inits on CHARACTER_POINTS_CHANGED, SPELLS_CHANGED, PLAYER_TALENT_UPDATE, CVAR_UPDATE(ShowAllSpellRanks) and UNIT_INVENTORY_CHANGED, then fires `CHECKERS_CHANGED` only when a range really moved. The Forever hunter harm list is only 75 and 2764, with no Arcane Shot or Raptor Strike. | **Subscribe to `CHECKERS_CHANGED`** as a rebuild trigger. WeakAuras does the same ([Prototypes.lua](https://raw.githubusercontent.com/WeakAuras/WeakAuras2/main/WeakAuras/Prototypes.lua)). |
| **RangeDisplay** v6.3.7 | Static user yard sections 5/20/30/35/40 on top of the LRC bracket. This is RangeMaster's model today. | No. |
| **Plater** ([Plater.lua](https://raw.githubusercontent.com/Tercioo/Plater-Nameplates/master/Plater.lua)) | One range per spec through `GetHarmMaxChecker`, refreshed 2 s after talent events. Auto-population of ranges is commented out: "it will reset ranges with talent changes". | **The lesson:** never overwrite edges the user set. Keep derived edges at runtime only. |
| **Hekili** ([HunterSurvival.lua](https://raw.githubusercontent.com/Hekili/hekili/thewarwithin/TheWarWithin/HunterSurvival.lua)) | Declares `RegisterRanges("raptor_strike","muzzle","arcane_shot")`, but the live path uses a static `nameplateRange`. | It confirms the anchor choice (melee, interrupt, ranged). |
| **ElvUI** ([Range.lua](https://raw.githubusercontent.com/tukui-org/ElvUI/main/ElvUI/Game/Shared/Modules/UnitFrames/Elements/Range.lua)) | Per-class spell lists filtered with `IsSpellInSpellBook`, rebuilt on spell and talent events. Skips CHARACTER_POINTS_CHANGED while points are unspent. Guards secrets. | The spellbook filter and the unspent-points skip. |

None of RangeDisplay, Plater, Hekili, WeakAuras or ElvUI derives bands dynamically. AppelSwingsForever (hunter-centric, Forever-only, fixed band list) is the only prior art for the owner's idea. RangeMaster would be the first to make it generic across classes and clients.

---

## 3. The mechanism

### 3a. Spell-defined bands (a predicate per band)

Per tick, for each unit, the engine asks each anchor role once. Roles are melee, ranged and long, plus friendly and pet where they apply. The question is `IsSpellInRange` on the first anchor in that role that is **known, usable, and not overridden**. Bands then match in order:

- `spell(role)`: holds when that role's anchor answers `true`.
- `gap`: the dead zone. The ranged anchor answers `false` and the melee anchor does not answer `true`. A shorter check also has to say "near": the RangeLens TooClose pattern, using a verified 20 yd item, interact distance 10 yd, or an LRC `maxYd` at or below the ranged anchor's max. Without that confirmation the result is `beyond`, or `unknown` when nothing answered.
- `beyond`: every spell band's anchor answered `false`, and the gap test failed.
- A `nil` from an anchor (spell unknown, unusable or invalid, or a secret) never counts as `false`. That band falls back to its yard edge (3b). If no rule and no yard can decide, the band reads **unknown**, never OOR. This follows the repo rule "Showing a range that is wrong rather than unknown" is an anti-goal, and research lesson 1.

### 3b. Yard edges computed from the spell's current range

At rebuild time each spell band gets `from` and `to` from `GetSpellInfo(activeAnchor)`, for example ranged = `minRange..maxRange`. This drives labels such as "8–41", the Bands editor read-out, and matching **only when the predicate gave nothing**.

### Why the hybrid, and not 3b alone

1. **GetSpellInfo and talents are UNVERIFIED.**
   - For "it includes talents": LRC re-inits on talent and glove changes, which only makes sense if the number moves (vendored `LibRangeCheck-3.0.lua` header line 12, and lines 4481-4497). RangeLens re-reads ranges "on talent changes". TrinityCore's `GetMaxRange` applies `SpellModOp::Range` ([SpellInfo.cpp](https://github.com/TrinityCore/TrinityCore/blob/master/src/server/game/Spells/SpellInfo.cpp), a server model).
   - Against: AppelSwings Yards.lua:966 distrusts "a spell's untalented range". The RangeLens README says a 10 yd icon "lights at 10 yards even when a talent makes the spell reach a little further". Yardstick (Era) computes Hawk Eye itself ([CurseForge](https://www.curseforge.com/wow/addons/yardstick)).
   - The [wiki](https://warcraft.wiki.gg/wiki/API_C_Spell.GetSpellInfo) says neither way.
2. **Computing it ourselves cannot work on Forever.** The DB2 collapses ranks: only 19498 has an effect row, BasePoints 6. Retail also has spell-label mods (auras 218/219) and mastery-scaled mods (Sniper Training 193468) that a static table cannot model ([Retail SpellEffect](https://wago.tools/db2/SpellEffect/csv?build=12.1.5.70961)).
3. **Gear, weapons and auras.** These move edges with no talent event: Sniper Shot's +10 yd for 3 shots on Forever (1310687), Libram of Awe 468913, Totem of Fiery Precision 446730, and the ranged-weapon `RangedModRange` (that last one UNVERIFIED on Forever). The predicate follows all of them for free.
4. **A straddling bracket stays wrong under 3b.** Even with a correct edge at 41, LRC's rungs (35, 40, 45 on Forever's Era tables) give brackets such as 40-45 that straddle 41 and still read OOR under `matchBy="max"`. The predicate answers that question directly.

A possible shortcut: the owner reports Arcane Shot "8-41". If that figure came from RangeMaster's own spell chip or tooltip, which reads `GetSpellInfo`, then Forever GetSpellInfo **does** include Hawk Eye and the M13 probe is already half answered. It is still UNVERIFIED until the owner confirms where the number came from.

### Concerns

- **Per-tick cost.**
  - Anchors are resolved at rebuild, so a tick costs at most 3-4 `IsSpellUsable` and `IsSpellInRange` calls per unit, short-circuited in band order (most units resolve on the first true).
  - It goes through the existing per-unit, per-tick memo in `modules/Range.lua:126-166`, so N containers on one unit still cost one evaluation.
  - The spell chips already ask the same calls through `NS.Range.InSpellRange` (`modules/Container.lua:612-650`), so sharing the memo makes chips and bands nearly free.
  - For 20 nameplates, about 60-80 C calls per tick. That is cheap, but M19 should confirm it with a perf scenario.
- **Honesty.** Each resolved band carries a provenance: `spell:<id>` (the predicate answered), `yards:derived` (the GetSpellInfo number, probe passed), or `yards:stored` (the preset or user number). The UI shows provenance. Unknown stays unknown.
- **Min-range spells and the dead zone.**
  - Talents move only the max (TrinityCore `GetMinRange` returns the raw value), so the Forever hunter dead zone stays at 8 yd stated for every build.
  - Stated yards are spell-check yards. Between two players that is about 11 yd centre to centre ([forever-hunter wiki](https://github-wiki-see.page/m/classic-hunter/forever-hunter/wiki/Anatomy-of-Range-Checks)).
  - Retail hunters have no dead zone: Auto Shot is 0-40 and SpellRange 114 has min 0 on Retail ([Retail SpellRange](https://wago.tools/db2/SpellRange/csv?build=12.1.5.70961), [Dead zone](https://warcraft.wiki.gg/wiki/Dead_zone)).
  - `Compat.spellRung` keeps rejecting min-range spells for the yard ladder, which is correct. Min-range anchors live only in the predicate path with TooClose.
- **Low-level characters.**
  - Each role holds an ordered fallback list and the first known spell wins (`IsPlayerSpell` / `IsSpellKnown`).
  - A role with no known anchor is marked *unresolved*. Its band uses `yards:stored` and the UI says "Raptor Strike not learned yet: using 5 yd".
  - Hunter Raptor Strike 2973 and Auto Shot 75 are L1, so hunters are always covered. Casters lack a baseline melee spell, so their band 1 stays yard- or interact-based (section 6).
- **Shapeshift and stance.**
  - Anchors are re-picked on `UPDATE_SHAPESHIFT_FORM` (druid: Claw 1082 in Cat, Maul 6807 in Bear, keyed by `GetShapeshiftFormID` as AppelSwings does).
  - The per-check `IsSpellUsable` gate stays.
  - The melee false-positive guard stays: void a non-hunter melee "true" when a verified 20 yd item says false.
- **Spell identity.**
  - Since 11.0.2, unlearned and off-spec spells give no answer, and hero-talent overrides break the original ID (LRC commits [cf92afa](https://github.com/WeakAuras/LibRangeCheck-3.0/commit/cf92afa6ebd895eb975ca0e0b55346cc5f631657), [5a653fb](https://github.com/WeakAuras/LibRangeCheck-3.0/commit/5a653fb0017f2effbab1d8d5be3d5d62befc03ab), [50a1a83](https://github.com/WeakAuras/LibRangeCheck-3.0/commit/50a1a83fe1e434d50da9a7415ec8ba776b11e2b1)).
  - Add a Compat shim, `Compat.AnchorInRange(id, unit)`. It resolves the override ID (`C_Spell.GetOverrideSpell`) and the localized name once per rebuild, then on Forever tries the name before the ID, as AppelSwings and RangeLens do.
  - Whether a rank-1 ID answers once a higher rank is learned on Forever is UNVERIFIED and goes into the probe.
- **Retail secrets.**
  - Spell-range booleans are documented without SecretReturns. UnitInRange has it ([UnitDocumentation](https://raw.githubusercontent.com/Gethe/wow-ui-source/live/Interface/AddOns/Blizzard_APIDocumentationGenerated/UnitDocumentation.lua)).
  - Behaviour on nameplates inside restricted content (M+, encounters) is UNVERIFIED ([Secret_Values](https://warcraft.wiki.gg/wiki/Secret_Values)).
  - Keep the `pcall` + `Compat.IsSecret` path in `rangeAnswer`, so a secret means unknown.
- **Fallback to yards.** Pure-yard bands and every unresolved spell band use today's `Resolve` path. NormalizeSet's numeric invariant still holds, because `from` and `to` stay finite numbers (the stored fallback).

---

## 4. Recompute triggers

All triggers go through `LIFECYCLE_EVENTS` with `ifValid` / `NS.SafeRegisterEvent` into the existing 0.5 s debounced `NS.Range.Rebuild()`, plus one settle re-read about 1 s later, because state can lag its event. Event existence is checked against Ketho Events.lua ([live](https://raw.githubusercontent.com/Ketho/BlizzardInterfaceResources/live/Resources/Events.lua), [forever](https://raw.githubusercontent.com/Ketho/BlizzardInterfaceResources/forever/Resources/Events.lua)).

| Event | Retail | Forever | Why |
|---|---|---|---|
| PLAYER_LOGIN / PLAYER_ENTERING_WORLD | yes | yes | initial resolve |
| SPELLS_CHANGED (exists today) | yes | yes | spells, forms, buffs; fires often on Forever |
| LRC `CHECKERS_CHANGED` callback | yes | yes | LRC's own debounced "a range moved" |
| CHARACTER_POINTS_CHANGED | yes | yes (main talent signal) | skip while points are unspent (ElvUI) |
| PLAYER_TALENT_UPDATE, TRAIT_CONFIG_UPDATED, TRAIT_CONFIG_LIST_UPDATED | yes | yes (Forever uses trait trees) | talents |
| ACTIVE_TALENT_GROUP_CHANGED, ACTIVE_PLAYER_SPECIALIZATION_CHANGED, PLAYER_SPECIALIZATION_CHANGED | yes | present | spec swap (Retail anchors are per spec) |
| PLAYER_PVP_TALENT_UPDATE | yes | present | PvP range talents (e.g. 203155) |
| LEARNED_SPELL_IN_SKILL_LINE | yes | yes | new rank or spell. **Do not** register LEARNED_SPELL_IN_TAB, which neither client has |
| PLAYER_LEVEL_UP / PLAYER_LEVEL_CHANGED | yes | yes | anchors unlock |
| UPDATE_SHAPESHIFT_FORM(S) | yes | yes | druid and other form anchors |
| PLAYER_EQUIPMENT_CHANGED / UNIT_INVENTORY_CHANGED("player") | yes | yes | ranged weapon, wand, libram, totem, gloves |
| UNIT_AURA("player"), throttled | optional | yes (Sniper Shot +10) | edge labels only. Predicates already follow auras |

The predicate path needs a rebuild only to re-pick anchors and refresh labels. Membership is live every tick, so a missed event can stale a label but never paint the wrong band. A rebuild sends `BANDSETS_CHANGED` only when a resolved anchor or edge actually changed, which avoids repaint storms from SPELLS_CHANGED.

---

## 5. Data model, schema, UI, migration, presets

### Band shape (schema v2)

```lua
band = {
  from = 8, to = 35,            -- finite fallback yards (unchanged invariant; user-editable)
  label, frameColor, textColor, indicatorColor, sound,   -- unchanged
  rule = nil                    -- pure yard band (today's behaviour)
       | { type = "spell", role = "melee"|"ranged"|"long"|"friendly"|"pet",
           spells = nil|{ id, ... } }   -- nil = class default anchors for role; list = user override
       | { type = "gap" }       -- between the previous and next spell bands (dead zone)
       | { type = "beyond" },   -- past the last spell band
}
```

Runtime-only resolution (never saved, which is the Plater lesson):

```lua
resolved[i] = { from = 8, to = 41, anchor = 3044, source = "spell"|"derived"|"stored" }
```

- A rule refers to a **role**, not a literal spell ID. That lets one "Hunter" preset carry across both clients, and every class gets a preset of the same shape.
- The class's anchor lists live in a new `SpellSeeds[client][class].anchors = { melee = {...}, ranged = {...}, long = {...} }` sub-table in `defaults/SpellSeeds.lua`. It is hand-kept, and optionally validated against wago.tools later (below).
- `Resolve(setId, state, minYd, maxYd, unit)`:
  1. If any band has a rule, evaluate spell bands in order through the per-tick memo.
  2. On no decision, fall through to today's yard match against `resolved[i]` edges.
- `matchBy` is unchanged and applies to the yard fallback.

### Settings UI (Bands tab)

- Each band row gets a **"Defined by"** dropdown: *Yards* / *Spell (role)* / *Dead zone (gap)* / *Beyond last spell*.
- For a spell rule:
  - a role dropdown, plus an optional spell-ID list edit with an icon and name preview;
  - a read-only line: "Now: Arcane Shot 3044, 8–41 yd (talents included)", or "Raptor Strike not learned: using 5 yd";
  - the existing "Up to (yards)" slider, relabelled **"Fallback (yards)"**.
- Band-span headers on the Band sets and Containers pages show the resolved span, with a small marker on spell-derived edges.
- `/rm get|set` still cannot reach bands. That is already a recorded Known Limitation.

### Migration v1 to v2 (`core/Database.lua`, `docs/schema.md`)

- Additive. `rule == nil` means a yard band, so every stored set keeps behaving exactly as today.
- Built-in presets that the user never edited (detect by preset id plus an unmodified flag or hash) are re-seeded to the new spell-rule presets.
- Customized copies are left alone. A one-time notice offers "Convert Hunter set to spell-defined bands".
- Do not silently rewrite user edges.

### Presets

- Each class preset becomes rule-based. Hunter on Forever: MELEE `spell(melee)`, DEAD `gap`, AUTO `spell(ranged)`, MARK `spell(long)` (optional), OOR `beyond`. Fallbacks 5/8/35/100.
- Retail Hunter drops DEAD, since there is no dead zone.
- `DefaultFor(class)` picks the class preset.

### Standards flag (CLAUDE.md requires raising this)

A nested `rule` table on a band is a non-scalar field in the schema-driven settings. The Bands editor rows already have no schema path, but the shape change and the new seed sub-table still need the owner's call. It is either a **documented deviation** (a row in `docs/ARCHITECTURE.md` under Documented deviations) or an **upstream change** to the WowAddonStandards schema rules. I could not resolve the exact `filename-§N` for the rule (UNVERIFIED). The Compat shim count in `docs/compat-layer.md` (18) also changes.

### wago.tools use

Not used at runtime. An optional generated, data-only file (a `validate-seeds` flow) can do two things:

- check that every anchor ID exists, with its base range and level, at the pinned builds: [SpellMisc](https://wago.tools/db2/SpellMisc/csv?build=1.60.1.70959) RangeIndex joined to [SpellRange](https://wago.tools/db2/SpellRange/csv?build=1.60.1.70959);
- list the known range talents per anchor (SpellEffect aura 107/108, misc 5, class-mask match), for tooltips ("Hawk Eye extends this").

It also catches stale seeds:

- The Retail DH ladder uses 183752, which 12.1.5 data puts at 0-5 melee, not 10-20.
- The Forever Hunter ladder `{1130}` has no rung between 35 and 100.

---

## 6. Per-class default band sets

Ranges are base hostile yards from DB2: Forever 1.60.1.70959 ([SpellMisc](https://wago.tools/db2/SpellMisc/csv?build=1.60.1.70959) / [SpellLevels](https://wago.tools/db2/SpellLevels/csv?build=1.60.1.70959)) and Retail 12.1.5.70961 ([SpellMisc](https://wago.tools/db2/SpellMisc/csv?build=12.1.5.70961)).

Talents are from SpellEffect aura 107/108 with misc 5 ([Forever](https://wago.tools/db2/SpellEffect/csv?build=1.60.1.70959), [Retail](https://wago.tools/db2/SpellEffect/csv?build=12.1.5.70961)).

Forever per-rank values are UNVERIFIED: only max-rank values are in the client data. "L" is BaseLevel.

### WoW Forever

| Class | Bands (role, then rule) | Anchor spells, in fallback order | Base | Range talents and mods |
|---|---|---|---|---|
| HUNTER | MELEE spell(melee) / DEAD gap / AUTO spell(ranged) / MARK spell(long) / OOR beyond | melee: Raptor Strike 2973 (L1), Wing Clip 2974 (L12), Mongoose Bite 1495. ranged: Auto Shot 75 (L1), Arcane Shot 3044 (L6), Serpent Sting 1978 (L4). long: Hunter's Mark 1130 (L6), Sniper Shot 1310687 (L40, 8-45) | 0-5 / 8-35 / 0-100 | Hawk Eye 19498 +6 flat (3 ranks; Era +2/+4/+6; IDs 19499/19500 have no client effect rows). Sniper Shot aura +10 for 3 shots. Does not affect Raptor Strike or Hunter's Mark (mask check) |
| WARRIOR | MELEE spell(melee) / CHARGE spell(ranged) / OOR beyond | melee: Heroic Strike 78, Rend 772, Hamstring 1715. ranged: Charge 100 (8-25, L4), Intercept 20252 (8-25), Throw 2764 / Shoot Bow 2480 / Shoot Gun 7918 (8-30, ranged weapon needed) | 0-5 / 8-25 or 30 | Greathelm of the Colossus 1306686 +1 melee (gear) |
| ROGUE | MELEE / RANGED (throw) / OOR | melee: Sinister Strike 1752, Gouge 1776, Kick 1766. ranged: Throw 2764 / Shoot (8-30), Distract 1725 (0-30, L22) | 0-5 / 8-30 | none found |
| PALADIN | CLOSE spell (10 yd) / RANGED / FRIENDLY / OOR | No baseline melee strike. close: Judgement 20271 (0-10, L4), Hammer of Justice 853 (0-10). ranged: Exorcism 879 (0-30, L20), Hammer of Wrath 24275. friendly: Holy Light 635 (40), Flash of Light 19750 | 0-10 / 0-30 / 40 | Enlightened Judgements 426173 +30 (SoD ID; obtainable? UNVERIFIED). Libram of Awe 468913 +20 Holy Shock (Holy Shock 20473: 20 hostile / 40 friendly) |
| PRIEST | NEAR (interact or wand) / CAST spell(ranged) / OOR | ranged, one per tree: Smite 585, Mind Blast 8092, SW:Pain 589 (0-30). short: Mind Flay 15407 (0-20). wand: Shoot 5019 (30). friendly: Lesser Heal 2050 (40) | 0-30 | Shadow Reach 17322 +20%. Holy Reach 27789 +10%. Improved Smite/Holy Fire 24482 +5 (set) |
| SHAMAN | MELEE (Stormstrike, if talented) / SHOCK 20 / CAST 30 / OOR | ranged: Lightning Bolt 403 (0-30, L1), Purge 370, Chain Lightning 421. short: Earth Shock 8042, Flame Shock 8050 (0-20). melee: Stormstrike 17364 (L40 talent). friendly: Healing Wave 331 (40) | 0-20 / 0-30 | Elemental Reach 28999 +6 (LB, CL, Fire Nova). Totem of Fiery Precision 446730 +5 Flame Shock. Improved LB 24462 +5 (set) |
| MAGE | NEAR / CAST spell(ranged) / OOR | ranged, one per tree: Fireball 133 (0-35), Frostbolt 116 (0-30), Arcane Missiles 5143 (30). short: Fire Blast 2136 (0-20). friendly: Arcane Intellect 1459 (30) | 0-30 or 35 | Flame Throwing 11100 +6. Arcane Geometry 11247 +6. Arctic Reach 16757 +10%. Improved Fire Blast 11078 +15. Conundrum +10 (gear) |
| WARLOCK | NEAR / CAST spell(ranged) / OOR | ranged, one per tree: Shadow Bolt 686, Corruption 172, Immolate 348 (30). short: Fear 5782, Drain Life 689 (0-20) | 0-30 | Destructive Reach 17917 +20%. Grim Reach 18218 +20%. Curse of Agony is renamed "Bane of Agony" 980, so use IDs, not names, for seeds |
| DRUID | MELEE (form-gated) / CAST spell(ranged) / OOR | melee: Claw 1082 / Shred 5221 (Cat), Maul 6807 / Growl 6795 / Bash 5211 (Bear). ranged: Wrath 5176 (0-30), Moonfire 8921, Entangling Roots 339. friendly: Healing Touch 5185 (40) | 0-5 / 0-30 | Nature's Reach 16819 +20% (Wrath, Moonfire, Starfire, Roots, FF, Hurricane, Insect Swarm) |

### Retail 12.1.5

There is no dead zone on Retail, so no class gets a `gap` band.

| Class | Bands | Anchors | Base | Range talents (TRAIT) |
|---|---|---|---|---|
| HUNTER | MELEE / RANGED / OOR (Survival: MELEE / HARPOON / RANGED) | melee: Raptor Strike 186270, Wing Clip 195645, Muzzle 187707. ranged: Arcane Shot 185358, Steady Shot 56641, Auto Shot 75, Cobra Shot 193455. long: Kill Command 34026 (50) | 0-5 / 0-40 | Precision Shot 428377 +10. Mastery: Sniper Training 193468 (scales). PvP Sniper Shot 203155 +30% |
| WARRIOR | MELEE / CHARGE / THROW / OOR | Slam 1464, Pummel 6552. Charge 100 (8-25). Heroic Throw 57755 (8-30). Taunt 355 (30) | | Javelineer 1271948 +5. Demolish 436358 +45 |
| PALADIN | MELEE / JUDGMENT 30 / FRIENDLY 40 / OOR | Crusader Strike 35395, Rebuke 96231. Judgment 20271, Avenger's Shield 31935 (30). Flash of Light 19750 (40) | | Jurisdiction 402971 +8 |
| ROGUE | MELEE / RANGED / OOR | Sinister Strike 193315, Kick 1766. Pistol Shot 185763 (20), Shuriken Toss 114014 (30), Poisoned Knife 185565 (30) | | Blinding Powder 256165 +5. Don't Be Suspicious 441415 +10. Toxic Stiletto 1267182 +3. Quick Decisions 382503 +20% |
| PRIEST | CAST 40 / OOR | Smite 585, SW:Pain 589, Mind Blast 8092, Penance 47540. friendly: Flash Heal 2061 | 0-40 | Phantom Reach 459559 (-13% or +15% by label, conflicting reads: UNVERIFIED) |
| DEATH KNIGHT | MELEE / RANGED 30 / OOR | Death Strike 49998, Heart Strike 206930. Death Coil 47541, Howling Blast 49184, Death Grip 49576 (30) | | Death's Reach 276079 +10 |
| SHAMAN | MELEE / CAST 40 / OOR | Primal Strike 73899, Stormstrike 17364, Lava Lash 60103. Lightning Bolt 188196, Flame Shock 188389 (40). Wind Shear 57994 (30) | | label-based totem mods only |
| MAGE | CAST 40 / OOR | Frostbolt 116, Fireball 133, Arcane Blast 30451, Fire Blast 108853 | 0-40 | none confirmed in findings |
| WARLOCK | CAST 40 / OOR | Shadow Bolt 686, Corruption 172, Agony 980, Incinerate 29722 | 0-40 | Improved Mortal Coil 1265816 +10. Teachings of the Black Harvest 385881 (label) |
| MONK | MELEE / RANGED / OOR | Tiger Palm 100780, Spear Hand Strike 116705. Crackling Jade Lightning 117952 (40), Provoke 115546 (30) | | Skyreach 392991 +5. Wind's Reach 450514 +5. Stormstout's Last Keg 383707 +10 |
| DRUID | MELEE (form) / CAST 40 / OOR | Shred 5221, Mangle 33917. Wrath 5176/190984, Moonfire 8921 (40) | | Astral Influence 197524 +5. Untamed Savagery 372943 +25% |
| DEMON HUNTER | MELEE / THROW 30 / OOR | Demon's Bite 162243, Chaos Strike 162794, Disrupt 183752 (0-5 in 12.1.5; the current seed is stale). Throw Glaive 185123, Torment 185245 (30) | | Improved Disrupt 320361 +5. Champion of the Glaive 429211 +10. Guile 1223171 +20 |
| EVOKER | CAST 25 / OOR | Azure Strike 362969, Living Flame 361469, Disintegrate 356995 (25) | 0-25 | Arcane Reach 454983 +5. Spatial Paradox 406732 (temporary) |

Notes:

- Retail per-spec preset variants (e.g. Survival vs BM/MM) are optional. The role model handles them through fallback order.
- Some Retail affected-spell targets come from label effects and are UNVERIFIED.

---

## 7. Risks, open decisions, milestones

### Risks

- **GetSpellInfo may be base on one client.** Then labels underestimate. Mitigation: provenance marks, and the predicate stays the source of truth.
- **LRC brackets on Forever may rest on unverified 40/45 yd Era items.** AppelSwings verified only 20/30/35 ([issue #45](https://github.com/WeakAuras/LibRangeCheck-3.0/issues/45) shows talents can even shift an item's range). Spell bands sidestep this. Pure-yard bands do not.
- **Item and interact checks are refused on friendly units in combat** ([CheckInteractDistance](https://warcraft.wiki.gg/wiki/API_CheckInteractDistance)). The `gap` confirmation then has only LRC's spell rungs. If unconfirmed, it reads beyond or unknown.
- **Melee anchors answering "in range" from anywhere** when unusable or out of form. Mitigation: the IsSpellUsable gate plus the 20 yd guard.
- **Name-first queries are locale-bound.** Resolve names from `GetSpellInfo(id).name` at rebuild, never from hard-coded strings.
- **Preview and Sim.** Test mode placeholder `{known,20,25}` uses InSpell=true, so every spell band would read "in". Sim must evaluate predicates against its fake distance. Its `inSpell` already reads GetSpellInfo.
- **Repaint storms** from SPELLS_CHANGED on Forever. Mitigation: send `BANDSETS_CHANGED` only on an actual change.

### Decisions for the owner (each with a recommended answer)

1. **Mechanism.** Recommend the hybrid: predicates decide membership, and yards are derived for labels and fallback.
2. **Trust GetSpellInfo numbers before the probe?** Recommend no. Show stored numbers marked "base" until M13 passes per client. Can you confirm where the "8-41" Arcane Shot figure came from? If it came from a RangeMaster chip, Forever already passes.
3. **Migrate existing sets?** Recommend auto re-seed only for unmodified built-in presets, plus a one-click convert offer for customized ones. Never silently rewrite.
4. **Schema shape.** Recommend `rule = {type, role, spells?}` with role-based defaults. Accept it as a documented deviation, or push it upstream to WowAddonStandards. Your call, per CLAUDE.md.
5. **Hunter's Mark "MARK" band (35-100)?** Recommend including it, off by default (AppelSwings has it).
6. **Caster band 1 with no melee spell.** Recommend a yard band backed by interact distance (10 yd duel) and items, not a spell band.
7. **Retail per-spec presets?** Recommend one class preset with role fallbacks first, and spec variants only if testing shows wrong anchors.
8. **wago.tools generated seed file?** Recommend yes, as a validation and tooltip source only (validate-seeds flow), never runtime math.
9. **UNIT_AURA trigger for Sniper Shot?** Recommend skipping it at first. Predicates already follow the aura, and only the label lags.

### Milestones (continuing the plan ledger after M12)

- **M13 — Probes and quirks.** These go into `docs/smoke-tests.md` and `docs/midnight-quirks.md`.
  - Forever: `/dump C_Spell.GetSpellInfo(3044).maxRange` and `(75)` with Hawk Eye at 0/3 and 3/3.
  - Rank-1 ID vs name answer for `IsSpellInRange` after rank 2 is learned.
  - Which LRC rung produced the "40" edge.
  - Retail: Wrath 5176 with Astral Influence 197524, and IsSpellInRange on nameplates in M+.
  - No code.
- **M14 — Compat and seeds.** Add `Compat.AnchorInRange` (override + name-first + pcall/IsSecret), the `anchors` sub-tables for both clients, and updated docs for the shim count. Tests for the shim under both kit profiles.
- **M15 — Anchor resolver and triggers.** Rebuild-time resolution (first known/usable anchor per role, derived edges with provenance), the event set from section 4 through `LIFECYCLE_EVENTS`, and the LRC `CHECKERS_CHANGED` subscription. Update the tests that read `NS.__lifecycleEvents`.
- **M16 — Resolve predicate path.** Spell, gap (TooClose) and beyond evaluation in the per-tick memo, shared with the chips. Unknown semantics. Preview and Sim support. Tests: the owner's case (bracket 35-40 with Arcane Shot true paints AUTO), dead zone, unlearned anchor, form gating, secret.
- **M17 — Schema v2 and presets.** The migration step, `docs/schema.md`, rule-based class presets for both clients, and the unmodified-preset re-seed.
- **M18 — Settings UI.** The "Defined by" control, role and spell override, resolved read-out, fallback slider, span markers. Update `docs/settings-panel.md`.
- **M19 — Verification.** Perf scenario (20 plates), in-game smoke on both clients, the deviation row or upstream change recorded, and the green gate (`lua tests/run.lua`, `KA0S_KIT_CLIENT=forever lua tests/run.lua`, bounded luacheck).

### Out of scope here

The other two items in the owner's request (label positions inside or outside on every side, and nameplate containers not showing) are separate work. M11 and M12 commits already touch label positions.


---

## Part 2. Critic review: spell-driven dynamic band sets

Sources I checked: the repo (read-only), wago.tools DB2 CSVs downloaded for Forever 1.60.1.70959 and Retail 12.1.5.70961 and saved at /tmp/claude-1000/-mnt-d-Profile-Users-Tushar-Documents-GIT-RangeMaster/e7e41098-6e8d-40b0-a994-41dd5558fae3/scratchpad/wago (query script: /tmp/claude-1000/-mnt-d-Profile-Users-Tushar-Documents-GIT-RangeMaster/e7e41098-6e8d-40b0-a994-41dd5558fae3/scratchpad/q.py), Gethe API docs, Ketho Events.lua, warcraft.wiki.gg, CurseForge, GitHub.

## Corrections

1. **The quote "accounts for talents" is attributed to the wrong API.** The sentence ("This takes into account talents, and can be used to determine the approximate distance...") is on the *legacy* `IsSpellInRange` page. That page lists it for Vanilla, TBC and Mists, with Retail removing it in 11.0.0 ([wiki](https://warcraft.wiki.gg/wiki/API_IsSpellInRange)). The [C_Spell.IsSpellInRange page](https://warcraft.wiki.gg/wiki/API_C_Spell.IsSpellInRange) says nothing about talents, and neither do the Gethe docs. So "the only range answer documented to include talent modifiers" holds only for the legacy API. For `C_Spell.IsSpellInRange` on Forever and Retail it is UNVERIFIED and belongs in the M13 probe. The predicate design still holds: RangeLens relies on the same assumption ("range talents are always included", [README](https://github.com/jonlipin/range-lens)). But the doc has to stop calling it documented.
2. **Two repo line citations are wrong.**
   - The Forever hunter preset is at `defaults/BandSetPresets.lua:55-69`. The file has 87 lines, so the cited 360-390 does not exist.
   - The chips' range calls are at `modules/Container.lua:685` and `:701`, not 612-650.
   - `BandSets.Resolve` (`modules/BandSets.lua:161-176`) and the memo in `modules/Range.lua` (about 150-166) are roughly right. Note that `Resolve` today has no `unit` parameter; the proposal adds one.
3. **The LibRangeCheck (LRC) trigger claims are overstated** (vendored `libs/LibRangeCheck-3.0/LibRangeCheck-3.0.lua:4965-4990`).
   - LRC registers `UNIT_INVENTORY_CHANGED("player")` only for MAGE and SHAMAN (gladiator gloves). A hunter gets no re-init or `CHECKERS_CHANGED` on a weapon swap.
   - It registers `LEARNED_SPELL_IN_TAB` and `PLAYER_TALENT_UPDATE` only when `C_EventUtils.IsEventValid` says they exist.
   - It does not register `TRAIT_CONFIG_UPDATED`, level-up, or shapeshift events.
   - Conclusion: `CHECKERS_CHANGED` cannot stand in for the proposal's own triggers. It only adds to them.
4. **The LRC Forever hunter harm list also contains Black Arrow 466930** (lines 221-226; it is added for every client). Only 75 and 2764 matter on Forever, so the point stands, but the list is not "only 75 and 2764".
5. **The ElvUI rule is misread.** ElvUI skips `CHARACTER_POINTS_CHANGED` when `not arg1 or arg1 > 0`, meaning a point was *gained* from levelling. It does not skip "while points are unspent" ([Range.lua](https://raw.githubusercontent.com/tukui-org/ElvUI/main/ElvUI/Game/Shared/Modules/UnitFrames/Elements/Range.lua)). The proposal's rule would miss a Hawk Eye rank spent by a levelling hunter who still has points left, which is the owner's exact situation.
6. **Phantom Reach 459559 is not "conflicting reads".** The Retail SpellEffect rows show two separate effects:
   - idx 0: aura 218 (label-based), +15, misc 5 (range).
   - idx 3: aura 108, -13, misc 5, class mask `[0,0,8224,0]`.

   So it is +15% for labelled spells and -13% for the masked ones. Both apply at once.
7. **AppelSwings provenance.** The cited CurseForge page ([appelswings](https://www.curseforge.com/wow/addons/appelswings)) is the Classic/TBC swing-timer AppelSwings (2.6.1), not AppelSwingsForever. Its page does not mention bands, Hawk Eye or `IsSpellInRange`. The page says AppelSwingsForever is a separate addon by the same author. I could not reach the local `/mnt/g/.../AppelSwingsForever` path. Everything attributed to it is UNVERIFIED by me: Bands.lua predicates, Yards.lua:966, v1.10.2, name-first queries, the Claw-from-40 yd guard.
8. **RangeLens "TooClose" is not in its README.** The README describes "Too close in orange: inside a spell's minimum range the icon turns orange". The claim that it "asks a shorter checker inside the spell's max" is a code-level claim I did not verify (UNVERIFIED). The README line about a 10 yd icon not lighting further out under a talent ("It never lights early") is real. It suggests its lit/unlit display is limited by its coarse probes, so it is not evidence against talents being included.
9. **The proposed shim duplicates existing ones.** `core/Compat.lua` already has shims 2-4: `IsSpellKnown`, `IsSpellUsable`, `SpellInRange`, all with `pcall` and `IsSecret` through `rangeAnswer`. `Compat.AnchorInRange` should combine them and add only override and rank resolution, not re-wrap the client calls. The count in `docs/compat-layer.md` is 18 today, as the proposal says.
10. **Rank handling on Forever should follow LRC.**
    - LRC never queries a hard-coded rank-1 ID. `findSpellIdx` looks up the spell **name** in the spellbook and uses that slot's spellID or index (lines 3860-3878).
    - The proposal's Hunter Forever anchors (2973, 3044, 75 and so on) are rank-1 IDs. `Compat.IsSpellKnown(rank1)` after a higher rank is learned is UNVERIFIED.
    - Fix: at rebuild, resolve each anchor to `C_Spell.GetSpellInfo(GetSpellInfo(id).name).spellID`. The docs say a name lookup checks overrides and the spellbook. Alternatively walk the spellbook. Then query that ID.
    - "Name first, then ID" per tick is weaker than this, and it also depends on locale.

## Gaps

- **Talent trigger on Forever.** The proposal says Forever "uses trait trees". The Forever DB2 has both `Talent` and `TraitTree` tables, and Ketho lists `CHARACTER_POINTS_CHANGED`, `PLAYER_TALENT_UPDATE`, `TRAIT_CONFIG_UPDATED` and `TRAIT_CONFIG_LIST_UPDATED` as present. Which of them actually fires on a Hawk Eye point is UNVERIFIED and needs a probe. Being present in the list does not mean it fires.
- **`CVAR_UPDATE` (ShowAllSpellRanks)** is missing from the trigger table, although LRC uses it on Forever and it affects name and rank lookups.
- **Pet anchors** need `UNIT_PET("player")` or `PET_BAR_UPDATE` for the `pet` role. The repo already has `UNIT_PET` in `LIFECYCLE_EVENTS`, but the proposal does not wire it to Rebuild.
- **`SPELL_RANGE_CHECK_UPDATE` / `EnableSpellRangeCheck`** exist on both Retail 12.1.5 and Forever 1.60.1 ([wiki](https://warcraft.wiki.gg/wiki/Event:SPELL_RANGE_CHECK_UPDATE)). They are push-based and target-only. The proposal does not consider them; they could cover the `target` unit cheaply.
- **Friendly units.** Harmful anchors answer nil on friendly targets, so friendly containers need the `friendly` role. Forever casters' friendly spells are mostly 0-40 (e.g. Holy Light 635: 0-40, verified). Spell bands under the `bandSetFriendly` override are not designed.
- **Dead or corpse targets and hostile players.** The nil-to-unknown path will paint unknown on corpses (no harmful answer). Melee reach against players and against large bosses differs from 5 yd. Forever Rangefinder notes "Enemy players have not been measured yet" ([CurseForge](https://www.curseforge.com/wow/addons/forever-rangefinder)).
- **Dead-zone confirmation.** Forever Rangefinder builds its hunter dead-zone warning from "the 5 yard check says no and the 8 yard check says yes" (item and interact checks). That is a tighter confirmation for `gap` than the proposal's 20 yd item.
- **Missed competitors**, all Forever- or Era-specific prior art for dynamic hunter zones:
  - [ForeverHunterDeadzone](https://www.curseforge.com/wow/addons/foreverhunterdeadzone): "Uses Hunter ranged abilities to determine shooting range", via WoW's range APIs, which is spell-driven.
  - [RangeBar (Hunter)](https://www.curseforge.com/wow/addons/rangebar-hunter): 8-35, "41 with Hawk Eye", per the search snippet.
  - [Forever Rangefinder](https://www.curseforge.com/wow/addons/forever-rangefinder): items and interact only.

  So the claim that AppelSwingsForever is "the only prior art" is wrong.
- **Usability edge cases.**
  - Auto Shot 75 with no ranged weapon or ammo: whether `IsSpellUsable` is false is UNVERIFIED. If it is, the fallback to Arcane Shot (L6) leaves L1-5 hunters with no ranged anchor.
  - Mongoose Bite 1495 is reactive, usable only after a dodge, so it is useless as a melee fallback.
- **Owner's "8-41".** Classic tooltips show the modified range server-side. The number may come from the spell tooltip rather than `GetSpellInfo`, so it is not proof for the M13 probe either way.
- **Retail secrets.** The 12.0 notes say spell APIs "including IsSpellInRange ... can now be called with secrets" ([12.0.0 notes](https://warcraft.wiki.gg/wiki/Patch_12.0.0/API_changes/notes)). That concerns secret *arguments* such as unit tokens. Return secrecy on nameplates in restricted content is still UNVERIFIED. The 12.0.5 PTR notes also say nameplate tokens are no longer handed out when unit identities are secret, which could hit the nameplate path upstream of any range call.
- **Stale upstream seed.** LRC itself labels 183752 "Consume Magic (20 yards)" (line 197). The DB2 has 183752 at Combat Range 0-5 on Retail 12.1.5. So the stale data is upstream in LRC too, not only in `defaults/SpellSeeds.lua:35`.

## Verified claims

- **Forever DB2** ([SpellMisc](https://wago.tools/db2/SpellMisc/csv?build=1.60.1.70959), [SpellRange](https://wago.tools/db2/SpellRange/csv?build=1.60.1.70959), [SpellEffect](https://wago.tools/db2/SpellEffect/csv?build=1.60.1.70959), SpellClassOptions):
  - Auto Shot 75 and Arcane Shot 3044 use RangeIndex 114 "Hunter Range", 8-35.
  - Raptor Strike 2973, Claw 1082, Maul 6807 and Stormstrike 17364 use RangeIndex 2 "Combat Range", 0-5.
  - Hunter's Mark 1130 is 0-100 ("Vision Range"). Sniper Shot 1310687 is 8-45 and its effect 1 is aura 107, +10, misc 5. Throw 2764, Shoot Bow 2480 and Shoot Gun 7918 are 8-30.
  - Hawk Eye 19498 effect 0: aura 107, BasePoints 6, misc 5. **19499 and 19500 have no SpellEffect rows.**
  - Class-mask check: Hawk Eye's mask hits Auto Shot, Arcane Shot, Serpent Sting, Concussive, Multi-Shot and Sniper Shot. It does **not** hit Raptor Strike, Wing Clip, Mongoose Bite or Hunter's Mark, as the proposal says.
- **Forever class anchors and talents** (DB2):
  - Ranges: Judgement 20271 and HoJ 853 are 0-10. Charge 100 and Intercept 20252 are 8-25. Fireball 133 is 0-35. Frostbolt, Smite, Shadow Bolt, Wrath, LB and Exorcism are 0-30. Fire Blast 2136, Mind Flay 15407 and Earth Shock 8042 are 0-20.
  - Talents: Flame Throwing 11100 is aura 107 +6. Arcane Geometry 11247 is 107 +6. Arctic Reach 16757 is 108 +10. Improved Fire Blast 11078 is 107 +15. Elemental Reach 28999 is 107 +6.
  - Talents (continued): Nature's Reach 16819, Shadow Reach 17322, Destructive Reach 17917 and Grim Reach 18218 are 108 +20. Holy Reach 27789 is 108 +10. Enlightened Judgements 426173 is 107 +30. Libram of Awe 468913 is 107 +20. Totem of Fiery Precision 446730 is 107 +5. Names come from SpellName.
- **Retail DB2** ([SpellMisc](https://wago.tools/db2/SpellMisc/csv?build=12.1.5.70961), [SpellEffect](https://wago.tools/db2/SpellEffect/csv?build=12.1.5.70961)):
  - Auto Shot 75, Arcane Shot 185358 and Wrath 5176 are 0-40 (no dead zone). Raptor Strike 186270 and Disrupt 183752 are 0-5.
  - Astral Influence 197524 is aura 107 +5 misc 5, plus label (219) effects. Sniper Training 193468 is aura 108 with bp 0 (mastery-scaled).
- **API shape on both clients** ([live](https://raw.githubusercontent.com/Gethe/wow-ui-source/live/Interface/AddOns/Blizzard_APIDocumentationGenerated/SpellDocumentation.lua), [forever](https://raw.githubusercontent.com/Gethe/wow-ui-source/forever/Interface/AddOns/Blizzard_APIDocumentationGenerated/SpellDocumentation.lua)):
  - `C_Spell.IsSpellInRange(spellIdentifier, targetUnit?)` returns `bool?`, flagged `SecretArguments = "AllowedWhenTainted"`, with no SecretReturns.
  - `GetSpellInfo` and `IsSpellUsable` are the same. `GetOverrideSpell` is `AllowedWhenUntainted`.
  - `SpellInfo` has `minRange` and `maxRange`.
  - `GetSpellInfo` accepts a name and "will always check for an override".
- **Whether `GetSpellInfo` ranges include talents**: genuinely undocumented ([C_Spell.GetSpellInfo](https://warcraft.wiki.gg/wiki/API_C_Spell.GetSpellInfo), [legacy GetSpellInfo](https://warcraft.wiki.gg/wiki/API_GetSpellInfo); the legacy page says only that form or stance may change returns). The UNVERIFIED label is correct.
- **Forever event presence** ([Ketho forever Events.lua](https://raw.githubusercontent.com/Ketho/BlizzardInterfaceResources/forever/Resources/Events.lua)):
  - Present: CHARACTER_POINTS_CHANGED, PLAYER_TALENT_UPDATE, TRAIT_CONFIG_UPDATED, TRAIT_CONFIG_LIST_UPDATED, ACTIVE_TALENT_GROUP_CHANGED, ACTIVE_PLAYER_SPECIALIZATION_CHANGED, PLAYER_SPECIALIZATION_CHANGED, PLAYER_PVP_TALENT_UPDATE, LEARNED_SPELL_IN_SKILL_LINE, PLAYER_LEVEL_UP, PLAYER_LEVEL_CHANGED, UPDATE_SHAPESHIFT_FORM(S), PLAYER_EQUIPMENT_CHANGED, UNIT_INVENTORY_CHANGED, SPELLS_CHANGED.
  - Absent: LEARNED_SPELL_IN_TAB.
  - Side note: PLAYER_FOCUS_CHANGED is also *present*, although the repo registers it `ifValid`.
- **LRC (vendored MINOR 39)**: `CHECKERS_CHANGED` fires only when `updateCheckers` reports a change (lines 4270-4290). Ranges come from `GetSpellInfo`, rounded with `math_floor(range+0.5)` (lines 3880-3888).
- **Repo**:
  - The Forever Hunter preset is 0-5 MELEE / 5-8 DEAD / 8-35 AUTO / 35+ OOR with `matchBy="max"`. Under `(from,to]` matching in `BandSets.Resolve`, a 35-40 bracket reads OOR, so the root-cause analysis is correct.
  - Forever seeds are `HUNTER chips {75,3044,1130}, ladder {1130}` (`defaults/SpellSeeds.lua:41`).
  - The Retail DH seed uses 183752 (`defaults/SpellSeeds.lua:35`).
  - `LIFECYCLE_EVENTS` (`core/RangeMaster.lua:65-84`) has only SPELLS_CHANGED as the spell trigger today.
  - `docs/midnight-quirks.md` already records "a known-but-unusable spell reports in range from anywhere" and "Forever item checks only at 20/30/35 yd". These back the IsSpellUsable gate and the 20 yd guard.
- **RangeLens** exists: Forever (Interface 16001), MIT, uses the game's own range check ([GitHub](https://github.com/jonlipin/range-lens)).
- **ElvUI** filters spells with `C_SpellBook.IsSpellInSpellBook(id, nil, true)` and guards secrets (URL above).
- **Not verified by me** (UNVERIFIED):
  - the LRC commit hashes cf92afa, 5a653fb and 50a1a83;
  - the Hekili, Plater and WeakAuras code claims;
  - the TrinityCore `GetMinRange` and melee-reach formulas (an emulator model in any case);
  - the Retail talent IDs I did not query: Precision Shot 428377, Javelineer 1271948, Jurisdiction 402971, Death's Reach 276079, Skyreach 392991, Arcane Reach 454983 and others;
  - the Era Hawk Eye per-rank +2/+4/+6 values.