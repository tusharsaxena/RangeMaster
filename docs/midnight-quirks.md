# Midnight quirks — Ka0s Range Master

This file has two parts: the collection's client-quirks catalog, vendored whole from the Ka0s WoW Addon Standard between the markers below and never edited here, and then this addon's own quirks under `## RangeMaster-specific quirks`.

<!-- BEGIN VENDORED: quirks catalog v2.113.0 (source: WowAddonStandards) -->
> Part of the **[Ka0s WoW Addon Standard](https://github.com/tusharsaxena/WowAddonStandards/blob/master/standards/STANDARDS.md)** — the split standard. This section is vendored whole into every addon's `docs/midnight-quirks.md` (§1), so its links are absolute. Cross-references use the `filename-§N` form (see the index's section map).

## Client quirks

The client behaviors the collection paid for more than once. Each entry here was discovered
**independently in two or more Ka0s repositories**, written up in each, and promoted by a harvest so the
next addon reads it instead of rediscovering it. A behavior one repo found stays in that repo's
`docs/midnight-quirks.md` until a second repo meets it.

*Why this section exists.* By 2026-11-06 eleven addons kept a private `docs/midnight-quirks.md`, 2,073
lines and about 133 entries between them, and about 81 of those entries were 21 behaviors written up
independently two to eight times. Nine of the eleven opened with their own restatement of the 12.0 secret
rules. Three write-ups contradicted this standard, and one contradiction was this standard's own error
(events-frames-taint-§2, *The combat-start edge*). A catalog was proposed and deferred twice, on
2026-08-25 and 2026-09-22, because an inventory rots; the build stamp per entry (§1) is the answer to that
objection (WowAddonStandards `harvests/2026-11-06/02_FINDINGS.md`, F3-01; every write-up quoted in
`harvests/2026-11-06/03_EVIDENCE.md`, Part A).

### 1. How an entry is written, and how it expires (MUST)

Every entry **MUST** carry:

- **The behavior**, stated as what the client does, not as advice.
- **Measured:** the client build or date it was observed on, where any write-up recorded one. An entry with
  no measurement says *not measured*; that is a weaker entry, not a missing field.
- **Cost:** what happened to an addon that did not know it.
- **Client:** the client it was measured on, `Retail` or `Forever` (clients-§1). An entry that names none is a Retail entry, which is every entry written before v2.103.0; a Forever behavior is written with `Forever` and its build, and it is not assumed to hold on Retail.
- **Do:** the workaround, as a rule an addon can follow.
- **Source:** the deepest write-up — the repo and document that probed furthest — and the harvest that
  promoted it. Every version is quoted in that harvest's `03_EVIDENCE.md`.

**Expiry.** An entry describes a client, and clients move. When the retail interface number moves past the
newest *Measured* stamp in an entry and an addon observes otherwise, the entry is corrected in a standard
release — not worked around in the addon. An entry nobody can reproduce moves to §6 as an open probe rather
than being deleted, because the behavior may only have moved.

**What an addon does with this section (MUST): carry it as a vendored block.** This section is the one
part of the standard an addon carries a **copy** of, because it is reference data about the game client
that a working addon needs offline, next to the code that works around it — not a rule, which is only ever
pointed at. Every addon's `docs/midnight-quirks.md` (documentation-§3) is two parts: the vendored block,
opened by a `BEGIN VENDORED` HTML comment naming the catalog's version and source and closed by an
`END VENDORED` HTML comment, each spelled exactly as `/dev-copilot:wow-revendor-standards` writes it; then
the addon's own section. The markers are described here rather than shown, because this text travels
inside them: a literal marker in the vendored copy would give the file a second end marker for the next
re-vendor to cut at.

```markdown
[the BEGIN VENDORED comment, stamped quirks catalog v<X.Y.Z>]
… this section, whole …
[the END VENDORED comment]

## <Addon>-specific quirks

… the addon's own quirks: one no second repo has met, its per-event costs, its own probe tables …
```

- The block is **copied whole and replaced wholesale** by `/dev-copilot:wow-revendor-standards`, stamped with
  the standard version it came from, under the same discipline as `libs/LibKa0s/` (anti-pattern #45): never
  a subset, **never edited inside the markers**. A local edit inside them is reverted by the next revendor,
  and the behavior it fixed comes back with no cause in the addon's history; a correction belongs in the
  addon's own section, where the next harvest finds it.
- The addon's own section **MUST NOT** restate a behavior the block carries. When a harvest promotes an
  entry, the revendor prunes the addon's copy: the upstream entry is the deeper write-up, and two live
  copies of one finding is the shape that drifted three times into contradiction.
- An addon with no quirks of its own still carries the block, with an empty own section.

**Contested behaviors are not rules.** Where two repos recorded opposite behavior and nobody has probed
the difference, the entry goes in §6 with both sides and the probe that would settle it.

Behaviors this standard already states elsewhere are not repeated here: the unknown-event raise
(events-frames-taint-§1), `Settings.OpenToCategory`'s numeric ID and collapsed parent (options-ui-§2),
the protected category switch in combat (options-ui-§2, anti-pattern #88), a secret through `tostring` and
`..` (events-frames-taint-§8), lockdown at `PLAYER_REGEN_DISABLED` (events-frames-taint-§2), the spec
readers' move to `C_SpecializationInfo` (compat, `LibKa0s-Compat-1.0`) and `SendChatMessage`'s move to
`C_ChatInfo` (compat).

### 2. Secret values

**A secret boolean cannot be tested at all.** `if`, `not`, `==` and `and`/`or` on a secret boolean raise
("attempt to compare … (a secret boolean value)"); the value is unusable in Lua, not merely unprintable.
`DurationObject`'s `HasExpired`, `HasStarted`, `IsActive` and `IsZero` come back secret in combat, and an
engine button's `IsShown` has answered a secret boolean out of combat. *Measured:* 12.0.7 (probe table);
12.1 (`IsShown`). *Cost:* a raise on every refresh tick of the path that tests it. *Do:* check
`issecretvalue` before any test; route a secret boolean to a C-side consumer
(`C_CurveUtil.EvaluateColorValueFromBoolean`, `SetAlphaFromBoolean`), or treat it as the cautious answer
(a secret lockdown reads as locked, a secret restriction as active, a secret claim as no claim). Two repos
disagree on whether to gate before the C-side call; that disagreement is recorded in `LibKa0s`
`docs/api/Compat` and is not ruled here. *Source:* KickCD `docs/midnight-quirks.md`, "Secret booleans are
unusable"; seven repos (harvest 2026-11-06, Q6).

**A secret cannot be a table key.** Indexing or assigning with a secret key raises "attempted to perform
indexed assignment on a table that cannot be indexed with secret keys". `UnitGUID` on a follower-dungeon
pet (`party3pet`) answers a secret string. *Cost:* a raise on every refresh tick for a roster keyed by
GUID. *Do:* guard a key with `IsSafeKey` (`LibKa0s-Compat-1.0`) or `issecretvalue` before keying; a
secret GUID is never a handle. *Source:* MultiMeters `docs/midnight-quirks.md`, the follower-dungeon pet
GUID; seven repos (Q7).

**A secret never reaches SavedVariables, and one that does is written as `nil`.** A value captured as
secret stays secret after combat ends, and the client writes a secret to SavedVariables as `nil` — or,
where it was a key, loses the entry. *Measured:* a reload probe, 2026-10-25. *Cost:* silent data loss on
the next reload. *Do:* store a plain value or nothing; never store a captured secret to read later.
*Source:* DpsRace `docs/known-limitations.md`, the reload probe; three repos (Q21).

**A frame handed a secret has secret geometry, and so does everything anchored to it.** After
`StatusBar:SetValue(secret)` (or `SetAlphaFromBoolean`, or anchoring to an aura engine container) the
frame `HasSecretValues`: its width, points and frame level read secret, out of combat too, and the
taint runs down the anchor chain to every frame anchored to it; a tooltip showing hidden information has
secret geometry. A secret size's `type` is `"number"`, so a type check lets it through, and
`BackdropTemplate`'s own arithmetic on a secret size raises. *Cost:* a raise inside Blizzard code, or a
layout computed from a secret. *Do:* compute layout from configuration and never read geometry back from a
frame that was handed a value; keep a record of the alpha you set rather than calling `GetAlpha()`; read a
frame level under a restricted anchor through a secret-safe guard (frame-layering). *Source:* AuraMaster
`docs/midnight-quirks.md`, the aura engine container entries (measured and dated); six repos and
`LibKa0s` `docs/api/Widgets` (Q8).

**A restricted spell's cooldown: branch on `isActive`, paint with the duration object.** In a restricted
state `C_Spell.GetSpellCooldown`'s timings are secret while `isEnabled` and `isActive` stay plain
(documented NeverSecret). `GetSpellCooldownDuration` answers a **zeroed** object, not `nil`, when there is
no cooldown, and a fresh object per call. *Cost:* raw `SetCooldown` with a secret start or duration raises;
a nil check passes the zeroed object. *Do:* decide from `isActive`; paint with
`Cooldown:SetCooldownFromDurationObject`, which accepts the object from tainted code. *Source:* KickCD
`docs/midnight-quirks.md`, the cooldown probe table; four repos (Q9).

**`notInterruptible` is secret, and the interruptibility events make it plain.** The cast info's
`notInterruptible` is secret; `UNIT_SPELLCAST_INTERRUPTIBLE` / `_NOT_INTERRUPTIBLE` deliver it plain.
`CastingBarFrameTemplate`'s built-in `OnUpdate` compares `GetTime()` with a secret `maxValue` and raises
when the bar shows another unit. *Do:* split the gate — the color path takes the secret C-side, the logic
path takes the event's plain value; do not inherit `CastingBarFrameTemplate` for a unit other than the
player. *Source:* KickCD `docs/midnight-quirks.md`, "split the gate in two"; two repos (Q13).

**`InChatMessagingLockdown` can answer a secret.** *Do:* read it through a guard and treat a secret as
locked. *Source:* DropWatcher and QuickComms `core/Compat.lua` (byte-identical), DpsRace; three repos (Q27).

### 3. Events

**A valid event can register without complaint and never fire.** `GUILDBANKFRAME_OPENED` registers and
never fires (*Measured:* 12.0.7); `UNIT_SPELLCAST_SUCCEEDED` is suppressed for protected interrupts;
`UNIT_HEALTH` and `UNIT_NAME_UPDATE` never fire for compound tokens such as `party1target`;
`GET_ITEM_INFO_RECEIVED` does not fire for an item already cached. This is the inverse of the
unknown-event raise (events-frames-taint-§1) and it is silent: nothing errors. *Cost:* a feature that
never runs, with nothing in the log. *Do:* confirm a new event fires in game before building on it, and
prefer an edge with a second source (a frame's `OnShow`, a gated timer) where the event is known to be
silent. *Source:* BankLedger `docs/midnight-quirks.md`, `GUILDBANKFRAME_OPENED`; four repos (Q20).

**Client state can lag its own event, or change with no event at all.** `IsMounted()` has flipped by the
time `PLAYER_MOUNT_DISPLAY_CHANGED` arrives while `C_PlayerInfo.GetGlidingInfo`'s `canGlide` sometimes has
not; after `INSPECT_READY` some slots still answer an item id with no link; switching bank tabs fires no
event, and the live warband tab has taken over a second to catch up; chat lockdown clears with no event.
*Cost:* a read at the edge answers the old state, and the display stays wrong until the next unrelated
event. *Do:* answer at the edge **and once more after a short settle** (a fraction of a second, a bounded
retry), never a poll. *Source:* MultiMeters `docs/midnight-quirks.md`, "some client state lags its own
event"; six repos (Q19).

**An empowered cast fires `UNIT_SPELLCAST_EMPOWER_*`, not the channel events.** `UnitChannelInfo`
reports it, but `UNIT_SPELLCAST_CHANNEL_START` / `_STOP` do not fire for it, and its release fires
`UNIT_SPELLCAST_SUCCEEDED` with the same cast GUID. *Do:* register the `EMPOWER_*` events wherever channels
are tracked. *Source:* KickCD `docs/midnight-quirks.md`, empowered casts; three repos (Q12).

**`ADDON_RESTRICTION_STATE_CHANGED` fires *before* enforcement.** The `Activating` state arrives before the
restriction begins, and access is still permitted during that dispatch; a dungeon restriction type has
gone active on entry and not cleared. Read the restriction type by its `Enum.AddOnRestrictionType` member
name — a member can be missing on some builds. *Measured:* 12.1.0, 2026-09-18. *Do:* treat `Activating`
as the last moment to read, not as the start of the restriction. The payload's second argument is
contested (§6). *Source:* AuraMaster `docs/midnight-quirks.md`, the restriction types; six repos (Q10).

### 4. Combat and secure frames

**Blizzard's aura buttons are forbidden to addon code, and `IsForbidden()` can say otherwise.** In
combat every call on a Blizzard aura button's objects raises "Attempt to access forbidden object from code
tainted by an AddOn"; in an instance (seen in Mythic+) the same buttons answer `IsForbidden()` `false` and
still refuse every read, `GetChildren` included. *Do:* never read Blizzard aura buttons; where a frame
must be inspected, `pcall` the read and treat a failure as forbidden. *Source:* PartyFrameEnhanced
`docs/midnight-quirks.md`, forbidden aura buttons; three repos (Q14).

**Escape runs a protected `Hide()` in combat.** A secure or protected frame listed in `UISpecialFrames` is
hidden by `CloseSpecialWindows`, which is a protected action in combat. *Do:* list a non-secure proxy in
`UISpecialFrames` and hide the protected frame from it out of combat, or keep protected frames out of the
list. *Source:* WhatGroup `docs/midnight-quirks.md`, the escape proxy; two repos (Q24).

### 5. Item, tooltip, enum and realm data

**Item data is nil until cached, and the load event has holes.** `GetItemInfo` answers nothing for an
uncached item; `GET_ITEM_INFO_RECEIVED` does not fire on an addon's first scan for an item the client
already holds; an uncached item's tooltip is not empty but a legible `RETRIEVING_ITEM_INFO` line; a failed
load drops its wait and nothing asks again. *Cost:* a blank or wrong row that never repairs. *Do:* load
through `LibKa0s-Item-1.0`'s cache-then-callback path (library-stack-§7), treat `RETRIEVING_ITEM_INFO` as
not-yet-loaded, and re-ask after a failed load. *Source:* ConsumableMaster `docs/midnight-quirks.md`, the
first-scan hole; seven repos (Q15).

**`C_TooltipInfo` returns raw templates.** Tooltip lines can carry the unexpanded plural grammar
`|4singular:plural;` (*Measured:* 12.1.5, "for the next 3 |4hour:hrs; 49 min") and a no-break space that
Lua's `%s` does not match. *Cost:* a parser that knew only the expanded words read no duration and called a
tradeable drop expired. *Do:* expand `|4…;` before matching, and match the no-break space explicitly.
*Source:* DropWatcher `docs/midnight-quirks.md`, the trade window; two repos (Q16).

**Tooltip line text can be secret** under an addon restriction, including through `TooltipDataProcessor`.
*Do:* guard each line before matching. *Source:* DropWatcher `docs/midnight-quirks.md`; two repos (Q17).

**Blizzard renumbers enums; resolve a member by name, never by number.** One build's
`Enum.TooltipDataLineType` and bank-tab values are not the next build's, and a member can be absent on a
build. *Cost:* a numeric guess for a member the build does not expose landed on an unrelated bank
container. *Do:* read `Enum.X.Member`, and handle its absence; localization-§4 already forbids the string
spelling. *Source:* DropWatcher `docs/midnight-quirks.md`, the research's enum values; five repos (Q18).

**`GetNormalizedRealmName` is nil early in login.** *Cost:* a stored `Name-` key with no realm. *Do:* never
build a `Name-Realm` key before the realm is known; defer, or fall back to `GetRealmName` with its spaces
and hyphens removed. *Source:* DropWatcher `docs/midnight-quirks.md`, realm names; four repos (Q25).

**On Forever a character's name is two words, unique per region, and its realm is a long label.** *Client:*
Forever (1.60.1, build 70790). *Measured:* the owner's in-game probe of 2026-11-08 (Ka0sAddonsCommonTasks
`docs/2026-11-07-WOW_FOREVER_PORT_STEP5/W1_FOREVER_NAME_PROBE.md`). Every character has a first name and a
surname, and only the pair is unique; `RegionalUniqueNamesEnabled()` answers true. The name APIs answer:

| Call | Forever answers | Retail answers |
|---|---|---|
| `UnitName(unit)`, `UnitFullName(unit)` | `"Traxex"`, `"Silentshot"`: the **surname** second | the name, then the realm (nil on your own realm) |
| `GetUnitName(unit, true)`, `Ambiguate(…, "short")` | `"Traxex Silentshot"` | `"Name"`, or `"Name-Realm"` across realms |
| a chat event's sender (arg 2) | `"Doom Dock"`, no realm suffix | `"Name-Realm"` |
| `GetRealmName()` / `GetNormalizedRealmName()` | `"CAMWOW AU1 Realm 2 PvP"` / `"CAMWOWAU1Realm2PvP"` | the realm, with and without its spaces |
| AceDB-3.0 40's `db.keys` | `char` `"Traxex Silentshot"`, `realm` `"PvP"`, `factionrealm` `"Alliance - PvP"` | `"Name - Realm"`, the realm |

Players know a realm by its ruleset (Normal, PvP, RP-PvP), not by its label, and there is no cross-realm play to
put a realm on another player. *Cost:* `local name, realm = UnitName(unit)` reads the surname as a realm and
builds `"Traxex-Silentshot"`; a one-value `UnitName(unit)` keeps only the first name, so two characters that
share one ("Traxex Silentshot", "Traxex Ironhide") collide in a key, a filter or a roster; a surface sized for
one Retail word truncates the pair; a `Name-Realm` key built from `GetNormalizedRealmName` is unique but is
not the identity the player or AceDB uses. *Do:* read a character through `LibKa0s-Compat-1.0`'s identity readers (from `LibKa0s v1.94.0`):
`UnitCharacterName(unit)` for any unit, `CharacterKey()` and `RealmKey()` for the player, and `RegionalNames()`
for the question itself. They implement this rule. When `RegionalUniqueNamesEnabled` exists and answers true,
a character's identity is its **whole name**: `GetUnitName(unit, true)` for any unit, or
`UnitNameUnmodified("player")`'s two returns joined by a space for the player, and its realm is the
**ruleset** AceDB 40 derives from `C_GameRules` (`Hardcore`, `RP-PvP`, `RP`, `PvP`, `PvE`). The ruleset is the realm key for stored realm data too, by the owner's
ruling of 2026-11-08, so two PvP realms share one realm key. An addon whose
profile store is AceDB reads those as `db.keys.char` and `db.keys.realm` and never derives them again. That
test is feature detection inside the compat family (clients-§3, compat), never a client check in feature
code. Never read `UnitName`'s second return as a realm, never split a name on whitespace or key on its first
word, and size every surface that shows a name, a realm or a profile key for the long form, or truncate it
with the whole value in a tooltip. *Source:* the owner's ruling and probe of 2026-11-08 during the WoW
Forever port's step 5, recorded ahead of the two-repo bar by that ruling; AceDB-3.0 minor 40's key block.

**A template-less `FontString` with no font raises on `SetText`.** "Font not set" from a `FontString`
created without a template or `SetFontObject` takes the addon down at load; a mock that does not enforce it
passes every test. *Do:* give every bare `FontString` a font object before its first `SetText`; the kit's
mock enforces it. *Source:* MultiMeters `tests/mock_frame.lua`, the font-not-set guard; three repos and
`LibKa0s` (Q22).

### 6. Open probes — contested behaviors (not rules)

Each needs an in-game probe, recorded with the build, before any section of this standard changes.

- **WoW Forever behaviors (one recorded).** The catalog was written on Retail. The Forever client (build 70790) has a missing-API surface, `SetDesaturation` among it, that LibKa0s tracks in LibKa0s#44. One Forever entry is in §5, the two-word names and long realm labels, measured on build 70790. Record any other Forever behavior in the repo that meets it, with the build, and promote it by a harvest like any other.
- **`string.format` on a secret.** events-frames-taint-§8 says it raises, with three repos; two say it
  works, one with a mid-combat observation. The likely difference is the specifier (`%s` against `%d` and
  `%.1f`) or that the result is itself a secret string. Probe each specifier, in combat, on a damage-meter
  value and a `UnitHealth` value. Until then §8's rule stands.
- **`ADDON_RESTRICTION_STATE_CHANGED`'s second argument.** One repo documents an
  `Enum.AddOnRestrictionState` value; three (one measured) record a boolean as well. Handle both shapes.
  The 2026-09-22 harvest called this settled, and it is not.
- **`SetAllPoints(parent)` on a secure button at load.** One repo records "Cannot anchor protected frames
  to regions" and uses the implicit-parent form; another anchors its secure rows with `SetAllPoints(row)`
  at birth and treats it as working, with its in-game smoke check still owed.
<!-- END VENDORED -->

## RangeMaster-specific quirks

The client behaviors this addon's code works around and the vendored catalog above does not carry.
None has been measured in a client by this addon yet: each is read from the reference addons, the
vendored LibRangeCheck-3.0 or Blizzard's generated API docs (the design's research,
`docs/superpowers/research/2026-11-18-range-research.md`), and each is a smoke check
(`docs/smoke-tests.md`) until a client run confirms it. A secret `UnitGUID` and forbidden frames are
the catalog's (sections 2 and 4) and are not restated here.

- **Item and interact range checks are refused in combat on a unit the player cannot attack.**
  `C_Item.IsItemInRange` and `CheckInteractDistance` are blocked for insecure code in combat on a
  friendly or other unattackable unit (the 10.2 rule); hostile units are fine. *Measured:* not
  measured; Blizzard's generated docs for Retail 12.1.5 (build 70783) and LibRangeCheck-3.0's
  `InCombatLockdownRestriction`. *Client:* Retail, and WoW Forever by the same client code. *Cost:*
  an `ADDON_ACTION_BLOCKED` per check. *Do:* in combat on a unit `UnitCanAttack` says no, ask spell
  checks only (`modules/Range.lua`'s ladder walk; LibRangeCheck does the same with its `*InCombat`
  lists). *Source:* the research, *API facts*.
- **WoW Forever's item checks are reliable only at 20, 30 and 35 yards.** Other item yards answer
  wrongly or not at all. *Measured:* not measured here; AppelSwingsForever `Bands.lua`, on Forever
  1.60.1. *Client:* Forever. *Cost:* a bracket edge at a yard the client does not honor. *Do:* keep
  Forever's item rungs at those three yards (`core/Compat.lua`, `FOREVER_ITEMS`). *Source:* the
  research, *WoW Forever*.
- **A spell can report "in range" from any distance.** On WoW Forever a melee spell whose range is
  0 to 0 does; on both clients a known spell that is unusable in the current form or stance can.
  *Measured:* not measured here; RangeLens and AppelSwingsForever. *Client:* Forever (the 0 to 0
  case), both (the form case). *Cost:* a container, a chip or a ladder rung that reads in range
  everywhere. *Do:* trust `C_Spell.IsSpellInRange` only for a spell that is known and usable, ask
  usability on every check (a shapeshift fires no `SPELLS_CHANGED`), and take a ladder rung only from
  a spell with a max range above 0 and no min range (`modules/Range.lua`, `core/Compat.lua`). A band
  anchor is asked the same way (`Compat.AnchorInRange`: known and usable first), and a non-hunter's
  melee anchor answering true is voided when LibRangeCheck's bracket starts at 20 yd or more (the
  melee guard, `modules/Range.lua`). *Source:* the research, *Lessons* 9, and the dynamic-bands
  research (`docs/superpowers/specs/2026-11-19-dynamic-bands-research.md`).
- **Whether a spell's reported range includes talents is undocumented.** `C_Spell.GetSpellInfo(id)`'s
  `minRange` / `maxRange` may be the base range (Auto Shot's 35 yd on WoW Forever) or the talented one
  (41 yd with Hawk Eye 3/3); whether `C_Spell.IsSpellInRange` itself follows the talent is equally
  undocumented for the `C_Spell` form. *Measured:* not measured; the wiki pages are silent, and the
  reference addons disagree (the dynamic-bands research, part 2). *Client:* both. *Cost:* a band
  read-out naming the base number, or, if `IsSpellInRange` ignored the talent, a spell band ending at
  the base range. *Do:* decide a spell band by the spell's answer, never by its reported number, and
  use the number only for the read-out and Sim; the stored yards stay the fallback
  (`modules/BandSets.lua`, `modules/Range.lua`). Smoke checks RANGE-6, RANGE-7 and RANGE-10.
  *Source:* the dynamic-bands research, part 1 section 3 and part 2.
- **On WoW Forever a spell has one ID per rank.** Whether a rank-1 ID still answers
  `C_SpellBook.IsSpellKnown` and `C_Spell.IsSpellInRange` once a higher rank is learned is unknown.
  *Measured:* not measured. *Client:* Forever. *Cost:* an anchor that reads as not learned, or a band
  that never holds, after a rank is trained. *Do:* resolve every seed to the current rank by name at
  rebuild (`Compat.CurrentSpellID`: `C_Spell.GetSpellInfo(name).spellID`) and rebuild on
  `LEARNED_SPELL_IN_SKILL_LINE`, `SPELLS_CHANGED` and `PLAYER_LEVEL_UP`. Smoke check RANGE-8.
  *Source:* the dynamic-bands research, part 2, correction 10.
- **Which event a WoW Forever talent point fires is unknown.** The client lists
  `CHARACTER_POINTS_CHANGED`, `PLAYER_TALENT_UPDATE`, `TRAIT_CONFIG_UPDATED` and
  `TRAIT_CONFIG_LIST_UPDATED`, and being listed does not mean firing. *Measured:* not measured.
  *Client:* Forever. *Cost:* a read-out that lags a spent point until the next rebuild. *Do:* rebuild
  on the first three wherever the client has them (`ifValid`, `core/RangeMaster.lua`'s
  `LIFECYCLE_EVENTS`) and on `SPELLS_CHANGED`, and never filter `CHARACTER_POINTS_CHANGED` on its points argument. Smoke check RANGE-9.
  *Source:* the dynamic-bands research, part 2, *Gaps* and correction 5.
- **`NAME_PLATE_UNIT_ADDED` can fire before the plate is populated.** *Measured:* not measured here;
  RangeLens's `OnPlateAdded` re-runs a frame later for it. *Client:* Forever. *Cost:* a container
  drawn at the screen's corner, or on no plate, until the next event. *Do:* re-check every added
  token one frame later (`modules/Anchors_Nameplate.lua`); the re-check runs on both clients, so no
  client branch sits outside the Compat layer. *Source:* the research, *WoW Forever*.
- **The token still resolves while `NAME_PLATE_UNIT_REMOVED` dispatches.** Inside the handler the
  removed `nameplateN` still answers, and `"target"` still answers the dying plate. *Measured:* not
  measured; read from the event order the anchors are built to. *Client:* both. *Cost:* a re-read
  sees the plate as live, and an own-plate container is put straight back on a plate that is going.
  *Do:* send `"none"` for the token outright (`NS.Ticker.Removed`), hide an own-plate container by
  comparing plate frames, and look again a frame later (`modules/Anchors_Nameplate.lua`).
  *Source:* `core/RangeMaster.lua`'s `OnNamePlateChanged`.
- **LibRangeCheck-3.0 caches per unit token when the GUID is a secret.** Its answer is kept 0.1 s,
  keyed by the token. *Measured:* read from LibRangeCheck-3.0 MINOR 39's source. *Client:* both.
  *Cost:* a retarget or a recycled `nameplateN` inside that window reads back the previous unit's
  bracket, and a 20 Hz ticker sees fresh data only every other tick. *Do:* call
  `GetRange(unit, true, nil, 0)` (a max cache age of 0) and keep this addon's own per-tick memo as
  the only cache (`modules/Range.lua`). *Source:* `modules/Range.lua`'s header.
