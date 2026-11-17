# Ka0s Range Master: design

Date: 2026-11-18 · Status: approved in conversation (mockup signed off); builder check folded in · Target: v0.1.0
Mockup: https://claude.ai/artifact/2ggGbFX18Ldydin4cT9pPJ (5 boards: in game, Containers page,
Band sets page, element gallery, presets). Research: `docs/superpowers/research/2026-11-18-range-research.md`.

## 1. Intent

A Ka0s collection addon that lets the player build **as many range displays ("containers") as they
want**, each watching one unit, styled independently, placed anywhere: free on screen, on a unit
frame, on a nameplate, or following the cursor. Range is shown as a number, a text label, an
indicator shape, spell-range chips, or any combination, and colours (frame, text, indicator)
follow the current **range band**. It ships with every standard Ka0s feature and runs on **Retail
and WoW Forever** from one codebase, even though the range-check spells and items differ per client.

Why: the existing range addons are either one-display-per-unit text boxes (RangeDisplay), tied to
one role (AppelSwings hunter bands), or nameplate-only (RangeLens). None gives free-form, multi-
container, per-container styling with the Ka0s settings experience on both clients.

## 2. Goals, non-goals, anti-goals

**Goals (v0.1.0)**
- Unlimited containers; per container: unit, band set, anchor, elements, style, visibility, sounds.
- Units: `target`, `focus`, `pet`, `mouseover`, and `nameplates` (every visible nameplate).
- Anchor modes: free (drag), unit frame (Blizzard + EllesmereUI providers, plus a manual frame name
  and click-to-pick), nameplate (the unit's own plate), cursor.
- Elements: number (6 formats), text label, indicator (dot, ring, square, diamond, triangle, bar,
  spell icon), spell-range chips. Any subset, reorderable, row or column.
- Colour by band for frame border, frame background, text and indicator; or fixed; or class colour.
- Shared, named **band sets** (owned at profile level, picked by containers), with class presets.
- Container **presets**: Simple, Intermediate, Advanced (first run + General › Presets).
- Band-change sounds (debounced), visibility rules, Test mode, Sim mode.
- All Ka0s standard features (launcher, LibKa0s options panel, profiles, skins incl. EllesmereUI,
  lock, slash get/set, debug console, diagnostics, perf, tests on both clients, docs set).

**Non-goals (v0.1.0, filed as issues)**
- Import/export strings. Party/raid/arena/boss units. ElvUI / SUF / Cell / other unit-frame
  providers. Edit Mode integration. A "true distance" estimator (AppelSwings-style Gauss-Newton).

**Anti-goals (would be failure even if it "works")**
- Showing a range that is wrong rather than unknown (a secret or nil result shown as out of range).
- Any taint or `ADDON_ACTION_BLOCKED` (nameplates, unit frames, settings panel), any Lua error from
  a secret value.
- A per-container OnUpdate or per-container range query: cost must scale with *units*, not containers.
- Retail-only behaviour sneaking into Forever (or the reverse) outside the Compat layer.

## 3. Constraints

- **Ka0s WoW Addon Standard** (current v2.113.0), scaffolded through the NEW_ADDON.md playbook
  (`/dev-copilot:wow-new-addon`). Clients value `Retail · Forever`: one unsuffixed TOC,
  `## Interface: 120105, 16001` (re-read live values at scaffold time). No root CHANGELOG.
- Stack: Ace3, LibStub, CallbackHandler, LibSharedMedia-3.0, LibDataBroker-1.1, LibDBIcon-1.0,
  vendored **LibKa0s** (newest tag), vendored **LibRangeCheck-3.0** (GitHub main, MINOR ≥ 39).
- Retail 12.x: `UnitInRange` is secret (unused); item/interact checks blocked on non-attackable
  units in combat (LibRangeCheck already falls back to spells); `UnitGUID` may be secret (key on
  unit tokens); nameplate frames may be forbidden (skip them).
- Forever: vanilla spells, only 20/30/35 yd item checks reliable, melee 0–0 spells useless for
  distance, plate data populates a frame after `NAME_PLATE_UNIT_ADDED`, focus may not exist (gate
  on `C_EventUtils.IsEventValid("PLAYER_FOCUS_CHANGED")`, not on project ID).
- No frame moves, reparents or re-anchors in combat; changes queue for `PLAYER_REGEN_ENABLED`.
  Exception: cursor-follow and nameplate containers are our own non-secure frames and may move.

## 4. Approaches considered

| Approach | Trade-off | Decision |
|---|---|---|
| **A. LibRangeCheck-3.0 + RangeMaster wrapper and per-client overrides** | Maintained upstream for Midnight and Forever; we add secret guards, caching and a vetted Forever ladder. Coarser than a bespoke estimator. | **Chosen** by the owner. |
| B. Own checker ladder per client (AppelSwings `Yards.lua` style) | Full control, finer numbers; we own every patch-day breakage, several times the work. | Rejected. |
| C. Blizzard-only signals (`IsActionInRange`, nameplate alpha) | Trivial, but no numbers and needs action slots. | Rejected. |

Band ownership: per-container vs **shared band sets** vs global: owner chose shared band sets.
Nameplates: unit's own plate vs every plate: owner chose **both**.

## 5. Design

### 5.1 Range engine (`modules/Range.lua`, `core/Compat.lua`)

- `Range.Get(unit)` → `state, minYd, maxYd` where `state ∈ {"known","unknown","none"}`
  (`none` = unit does not exist). Wraps `LRC:GetRange(unit, true)` in `pcall`; any secret
  (`issecretvalue`) or error → `unknown`. `max == nil` with a min → `known` open-ended (`45+`).
- Per-tick memo keyed by unit token (`nameplateN` included): N containers on one unit = one query.
- `Compat.RangeOverrides()` returns per-client checker adjustments applied through LRC's public
  checker hooks where available; otherwise a small RangeMaster ladder consulted first for the
  brackets LRC gets wrong on Forever (20/30/35 items, interact 3/4 race-adjusted, class spells
  from a seed table `defaults/SpellSeeds.lua` keyed `[client][class]`). Builder decides the exact
  mechanism after reading LRC's API; the contract above is fixed.
- `Range.InSpellRange(spellID, unit)` → `true|false|nil` via `C_Spell.IsSpellInRange`, guarded,
  and only for spells known to the player (`IsPlayerSpell`/`C_SpellBook`).
- **Ticker** (`modules/Ticker.lua`): one `C_Timer` ticker. 10 Hz out of combat, 20 Hz in combat,
  stopped when no enabled container has a live unit. Forced refresh on `PLAYER_TARGET_CHANGED`,
  `PLAYER_FOCUS_CHANGED` (if valid), `UNIT_PET`, `UPDATE_MOUSEOVER_UNIT`,
  `NAME_PLATE_UNIT_ADDED/REMOVED`, `PLAYER_REGEN_*`, `SPELLS_CHANGED` (debounced: rebuild seeds).
  Mouseover re-validates `UnitExists("mouseover")` every tick. Sends `NS.Bus` messages
  `RANGE_UPDATED(unit)` only when that unit's (state,min,max) changed.

### 5.2 Data model (AceDB, `defaults/Profile.lua`, `core/Database.lua`)

```
profile.containers[id]  = CONTAINER_TEMPLATE (deep-copied on create; missing keys filled on load)
profile.containerOrder  = { id, ... }       profile.nextContainerId = n
profile.bandSets[id]    = BANDSET_TEMPLATE   profile.bandSetOrder, profile.nextBandSetId
profile.seeded          = bool (first-run preset picker shown/applied)
global.schemaVersion = 0, global.minimap = { hide = false }
```

CONTAINER_TEMPLATE:
```
name, enabled=true, unit="target", bandSet=<id>, bandSetFriendly=nil (nil = use bandSet for every reaction),
anchor = { mode="screen"|"frame"|"nameplate"|"cursor",
           frame = { provider="blizzard"|"ellesmere"|"custom", name="" },
           point="CENTER", relPoint="CENTER", x=0, y=0, strata="MEDIUM" },
layout = { direction="row"|"column", spacing=4, padding=4, scale=1, alpha=1 },
frame  = { border = { enabled, texture(LSM), size, colorMode="band"|"fixed"|"class", color },
           background = { enabled, colorMode, color, bandAlpha=0.15 } },
elements = {
  order = { "indicator", "number", "text", "spells" },
  number    = { enabled=true, format="range"|"max"|"min"|"under"|"approx"|"suffix",
                font, size, outline, colorMode, color },
  text      = { enabled=false, font, size, outline, colorMode, color, upper=true },
  indicator = { enabled=false, shape="dot"|"ring"|"square"|"diamond"|"triangle"|"bar"|"icon",
                size=12, colorMode, color, spellID=nil (icon shape; nil = first spell chip) },
  spells    = { enabled=false, list = { spellID, ... } (per client+class seeded), style="chip"|"icon", size },
},
visibility = { combat="any"|"in"|"out", reaction="any"|"hostile"|"friendly",
               hideNoUnit=true, oocAlpha=1 },
sounds = { enabled=false, channel="Master" },
nameplate = { includeFriendly=false, point="TOP", relPoint="BOTTOM", x=0, y=-2 },
```

BANDSET_TEMPLATE: `name, matchBy="max"|"min", unknown = { label="?", color=grey },
bands = { { from, to (nil = ∞), label, frameColor, textColor, indicatorColor, sound=LSM|nil }, ... }`.
Bands are ordered, non-overlapping; the editor normalises edges (band n's `from` = band n-1's `to`).

Preset band sets (class-aware default picked on first run): **Melee / Ranged** (0–5 MELEE, 5–20
CLOSE, 20–30 MID, 30–40 LONG, 40+ OOR), **Caster 40**, **Healer** (friendly: 0–30, 30–40, 40+),
**Hunter** (Forever: 0–5 MELEE, 5–8 DEAD, 8–35 AUTO, 35+ OOR; Retail: 0–5, 5–40, 40+).
Colour default ramp: `#4ade80 #a3e635 #facc15 #fb923c #ef4444`, unknown `#9ca3af`.

Container presets (`modules/Presets.lua`), applied via ContainerManager only:
- **Simple**: Target, Focus, Pet, Mouseover; free on screen; number + band-coloured border.
- **Intermediate**: Target/Focus/Pet on their unit frames, Mouseover on cursor; number + text + dot;
  hostile vs friendly band sets; hide out of combat with no unit.
- **Advanced**: Intermediate + target on its own nameplate (diamond + number) + All nameplates
  (dot + short number) + Focus with spell chips + OOR sound + visibility rules.
Applying replaces the profile's containers after a confirm; one-level Undo (snapshot).

### 5.3 Containers and rendering

- `modules/ContainerManager.lua`: sole writer of the container list (Create, Delete, Duplicate,
  Rename, UniqueName, CopySettings, Snapshot/Restore, ApplyPreset); coalesces applies to next frame,
  defers in combat; sole sender of `CONTAINERS_CHANGED`. Same contract as AuraMaster's.
- `modules/BandSets.lua`: CRUD for band sets; `BandSets.Resolve(setId, state, min, max)` → band
  index or `unknown`. Deleting a band set in use reassigns users to the default set (confirm).
- `modules/Container.lua`: one frame per container (pooled), child elements per `elements.order`.
  `Container:Render(state, min, max, spellResults)` (band resolved with `bandSetFriendly` when the
  unit is friendly and the override is set; else `bandSet`) sets text only when changed, recolours only
  when the band index changed. `nameplates` containers own a pool of per-plate instances keyed by
  plate token.
- `modules/Elements_*.lua`: Number (format functions), Text, Indicator (textures in
  `media/indicators/`, drawn shapes via textures, no SVG), Spells (chip = coloured icon border).
- Number formats on (20, 25): range `20–25`, max `25`, min `20`, under `<25`, approx `~22`,
  suffix `25 yd`. Open-ended: `40+`. Unknown: band set's unknown label.

### 5.4 Anchors (`modules/Anchors*.lua`)

- `screen`: draggable when unlocked (LibKa0s drag handle), position saved as point/x/y.
- `frame`: provider resolves a frame per unit: Blizzard (`TargetFrame`, `FocusFrame`, `PetFrame`;
  mouseover has no frame → falls back to cursor), EllesmereUI (frame names resolved at runtime when
  the addon is loaded; through LibKa0s where it offers a lookup, never reading `EllesmereUIDB`),
  `custom` (global name, re-resolved on `ADDON_LOADED`; click-to-pick picker walks to the nearest
  named ancestor). Missing frame → container hidden + one debug-log line, never an error.
- `nameplate`: for `target`/`focus`/`mouseover`, `C_NamePlate.GetNamePlateForUnit(unit)`; re-anchor on
  unit change and `NAME_PLATE_UNIT_ADDED/REMOVED` with a one-frame re-check. For unit `nameplates`
  every plate gets an instance (hostile only unless `includeFriendly`). Forbidden plates skipped.
  Pet has no plate in practice → hidden.
- `cursor`: OnUpdate-free follow driven by the shared ticker's frame hook (or a single shared
  OnUpdate for all cursor containers), `GetCursorPosition()/UIParent:GetEffectiveScale()` + offset.

### 5.5 Behaviour

- **Visibility**: evaluated on unit change, combat change and reaction change; `oocAlpha` applies
  out of combat. Master visibility (General) wraps everything (Ka0s 4-value dropdown).
- **Sounds**: not offered for `nameplates` containers (Sounds rail section hidden; 20 plates would
  chain-fire). Per-band state (current band, settle timer, first-band flag) lives on the render
  instance (one per container, one per plate for `nameplates`). On entering a band with a sound; settle 0.2 s, gap ≥1 s per container, silent on the
  first band after the unit changed; LSM sounds; channel per container.
- **Test mode** (checkbox, `/rm test`, launcher): every enabled container shows a placeholder
  reading through the real render path; TestStrip marker; ends on combat; refuses in combat.
- **Sim mode** (checkbox next to Test mode, `/rm sim`, launcher): LibKa0s-Sim drives a fake distance
  sweeping 0→50→0 yd over ~20 s for every container, firing band changes and sounds. Ends on combat.
- **Lock**: Master controls + launcher; unlocked shows drag handles on `screen` containers.

### 5.6 Settings panel (LibKa0s-Options)

Landing page; **General** (Master controls tab in canonical order incl. Test + Sim; Presets tab;
Skin tab; Keybindings only if Bindings.xml); **Containers** (banner picker + New container; rail:
General · Display · Indicator · Visibility · Sounds; live preview of every band; Duplicate / Copy
settings from / Delete); **Band sets** (picker + New / Duplicate; distance ribbon; reorderable band
rows with from / to / label / 3 colours / sound; match-by; unknown label); **Profiles**. Opening in
combat is refused with a gray line. Rows use `container.*` / `bandSet.*` paths resolved against
the selected item, so `/rm get|set` works on them.

### 5.7 Slash

`/rm` and `/rangemaster`. Reserved verbs per the standard plus: `containers`, `select <n>`,
`new [unit]`, `delete <n>`, `pick`, `bands`, `preset simple|intermediate|advanced`, `test`, `sim`.

### 5.8 Roster row

`Ka0s Range Master | ../../RangeMaster/ | https://github.com/tusharsaxena/RangeMaster | Retail · Forever |
Enabled · Locked · Test mode · Sim mode | test | next to Test mode`.

## 6. Testing

Headless kit suites under `KA0S_KIT_CLIENT=retail` and `=forever`: Range wrapper (secret → unknown,
error → unknown, open-ended, memo), BandSets.Resolve (edges, matchBy, unknown), number formats,
ContainerManager CRUD + presets + undo, visibility evaluation, sound debounce, anchor resolution
with missing frames, nameplate instance pooling, surface parity, vendor sync, disabled lifecycle,
perf scenarios (10 containers + 20 plates per tick). In-game smoke list in `docs/smoke-tests.md`.

## 7. Left to the builder

- Exact LRC override mechanism; exact EllesmereUI frame names (verify against the installed addon
  under `_retail_` and `_forever_` AddOns); indicator texture art; font defaults; the Advanced
  preset's spell chip seeds per class/client (validated against the client spell tables we can read).
- Everything the standard prescribes (file layout, setup descriptors, docs set) follows NEW_ADDON.md.
